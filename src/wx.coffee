# ### 内部模组
fs         = require 'fs'
path       = require 'path'
crypto     = require 'crypto'
{exec}     = require 'child_process'

# ### 外部模组
redis      = require 'redis'
_          = require 'underscore'
_s         = require 'underscore.string'
request    = require 'request'
getRawBody = require 'raw-body'
xml2js     = require 'xml2js'
express    = require 'express'
async      = require 'async'

# ### 接口地址
#
# + 大部分接口地址；
# + 二维码接口地址；
# + BINARY上传地址。
api_common = 'https://api.weixin.qq.com/cgi-bin'
api_qrcode = 'https://mp.weixin.qq.com/cgi-bin'
api_binary = 'http://file.api.weixin.qq.com/cgi-bin'

# 构造函数接收以下参数：
#
# + 在`微信公共平台 > 功能 > 高级功能 > 开发模式`中获取：
#
#   - `token`
#   - `app_id`
#   - `app_secret`
#
# + `redis`：`REDIS`连接参数（默认本地连接），包含：
#
#   - `port`
#   - `host`
#   - `options`
#
# + `populate_user`：是否自动组装用户信息，默认`on`；
# + `debug`：调试模式，输出调试信息。
module.exports = ({token, app_id, app_secret, redis_options, populate_user, debug}) ->

  # ### REDIS客户端
  #
  # 创建`2`个`REDIS`客户端：
  #
  # + 消息订阅专用客户端。
  # + 其余通用操作客户端；
  {port, host, options} = redis_options ? {}
  redis_pubsub = redis.createClient port, host, options
  redis_client = redis.createClient port, host, options

  # 访问口令局部缓存。
  access_token = null

  #（默认）响应消息前，先通过微信接口组装用户信息。
  populate_user ?= on

  # ### 处理句柄
  #
  # + 点击各个按钮的处理句柄；
  # + 扫描不同二维码处理句柄；
  # + 响应不同文字消息的句柄。
  @click_handlers = {}
  @scan_handlers  = {}
  @text_handlers  = []

  # ### 二维码参数
  #
  # 永久二维码最多个数：`100000`个；
  # 临时二维码超时时间：`1800`秒；
  # 二维码查询超时时间：`30`秒。
  qrcode_permanent_maximum = 100000
  qrcode_temporary_expires = 1800
  qrcode_long_poll_timeout = 30
  qrcode_permanent_channel = 'permanent'

  # ### 未响应的二维码请求
  #
  # + 未响应的桌面请求；
  # + 未响应的微信请求。
  unsent_dt_responses = {}
  unsent_mb_responses = {}
  
  # ### `REDIS`订阅：
  #
  # + `WX:ACCESS_TOKEN`：访问令牌自动更新事件；
  # + `WX:SCAN:TEMPORARY`：从另外进程接收到的临时二维码扫描事件；
  # + `WX:SEND:MOBILE` ：在另外进程模拟的被动响应消息发送；
  # + `WX:SEND:DESKTOP`：在另外进程模拟的发送桌面端响应。
  #
  # 消息内容均为`JSON`格式。
  redis_pubsub.subscribe 'WX:ACCESS_TOKEN', 'WX:SCAN:TEMPORARY', 'WX:SEND:MOBILE', 'WX:SEND:DESKTOP'
  redis_pubsub.on 'message', (channel, message) =>
    message = JSON.parse "#{message}"
    switch channel

      # `ACCESS_TOKEN`事件时：更新访问口令局部缓存：
      when 'WX:ACCESS_TOKEN' then access_token = message

      # `WX:SCAN:TEMPORARY`事件时：
      when 'WX:SCAN:TEMPORARY'

        # 寻找未响应的桌面端请求、响应对象，
        # 找不到表示桌面端查询非本进程处理。
        # console.log '查找桌面查询', message.id
        return unless dt_res = unsent_dt_responses[message.id]
        delete unsent_dt_responses[message.id]
        # console.log '找到了桌面查询', message.id
        [session, name, query] = JSON.parse message.id
        [req, res] = dt_res

        # 服务器端已定义处理句柄时：
        if scan_handler = @scan_handlers[name]

          # + 用原始扫码消息增补请求对象。
          # + 用传入消息的`user`键，增补请求对象的`user`键，并具备客服消息回复功能。
          _(req).extend(message.content)
          _(req.user ?= {}).extend(message.user, user_actions)

          # 调用扫码处理句柄参数为：
          #
          # 1. `请求`对象：来自桌面端的原始查询请求；
          # 2. `手机`对象：支持全部微信被动回复方法；
          # 3. `桌面`回掉：模拟成桌面端注册回调方法。
          mobile  = reply req, message.id
          desktop_callback = -> res.send [message.msg_id].concat Array::slice.call arguments
          scan_handler req, mobile, desktop_callback

        # 否则（有桌面端监听扫码结果，服务器端未定义如何处理时），
        # （默认）向桌面端发送扫码用户。
        else res.send [message.user]

      # `WX:SEND:MOBILE`事件时：
      #
      # 1. 定位对应的未回复微信响应；
      # 2. 删除缓存的未回复微信响应；
      # 3. 向微信端被动回复指定消息。
      when 'WX:SEND:MOBILE'
        return unless mb_res = unsent_mb_responses[message.id]
        delete unsent_mb_responses[message.id]
        mb_res[message.type] message.content

      # `WX:SEND:DESKTOP`事件时：
      #
      # 1. 定位对应的未回复桌面连接；
      # 2. 删除缓存的未回复桌面连接；
      # 3. 向桌面端发送指定扫码消息：
      #    + 永久二维码缓存多组桌面连接；
      #    + 临时二维码缓存单组桌面连接。
      when 'WX:SEND:DESKTOP'
        return unless dt_res = unsent_dt_responses[message.id]
        delete unsent_dt_responses[message.id]
        [session, name, query] = JSON.parse message.id
        if name is qrcode_permanent_channel
          for [req, res] in dt_res
            res.send message.content
        else dt_res[1].send message.content

  # ### 创建路由器
  wx = router = express.Router()

  # ### 获取访问令牌
  lock_fetching = 5
  do fetch_access_token = =>
    redis_client.watch 'WX:ACCESS_TOKEN'
    redis_client.ttl 'WX:ACCESS_TOKEN', (err, ttl) =>
      redis_client.get 'WX:ACCESS_TOKEN', (err, _access_token) =>
        if ttl > lock_fetching
          redis_client.multi().exec (err, multi_res) =>
            return fetch_access_token() unless multi_res
            access_token = _access_token
            setTimeout fetch_access_token, (ttl - lock_fetching) * 1000
        else if "#{_access_token}" not in ['FETCHING']
          redis_client.multi()
          .setex('WX:ACCESS_TOKEN', lock_fetching, 'FETCHING')
          .exec (err, multi_res) =>
            return fetch_access_token() unless multi_res

            # 用`app_id`与`app_secret`，发起访问令牌请求。
            request
              method : 'GET'
              url    : "#{api_common}/token?grant_type=client_credential&appid=#{app_id}&secret=#{app_secret}"
              json   : on
            , (err, res) =>

              # 网络异常时，立即重试。
              return fetch_access_token() unless res

              # 存在错误代码时，控制台提示，删除令牌。
              if res.body.errcode
                console.error '微信认证失败，登录微信公共平台获取开发者凭据 https://mp.weixin.qq.com'
                redis_client.del 'WX:ACCESS_TOKEN'
              else
                {access_token: _access_token, expires_in} = res.body
                redis_client.setex 'WX:ACCESS_TOKEN', expires_in, _access_token
                redis_client.publish 'WX:ACCESS_TOKEN', JSON.stringify _access_token
                setTimeout fetch_access_token, (expires_in - lock_fetching) * 1000
        else setTimeout fetch_access_token, ttl * 1000

  # ### 二维码请求预处理
  #
  # 根据获取二维码或查询二维码扫码结果请求，确定二维码名称与标识。
  identify_qrcode = (req) ->

    # 每个二维码关联参数：
    #
    # + 会话
    # + 名称
    # + 查询
    session = req.session.id
    name    = (req.params.name ? '').toLowerCase()
    query   = req.query
    delete query.t

    # 调整永久二维码名称为`permanent`，查询为场景编号。
    if 1 <= name <= qrcode_permanent_maximum
      session = ''
      query   = _(scene_id: +name).extend(req.query)
      name    = qrcode_permanent_channel

    [session, name, query]

  # ### 获取二维码
  #
  # `/qrcode`后可选二维码名称，对应不同处理句柄。
  router.get '/qrcode/:name?', (req, res) =>
    [session, name, query] = identify_qrcode req

    # 微信返回二维码票据后：
    #
    # 1. 根据二维码类型，生成票据。
    # 1. 在`REDIS`中将该票据与参数进行关联，`1800`秒后自动过期；
    # 2. 将图片请求重定向至微信服务器二维码图片生成地址。
    create = (scene_id) ->
      json =
        'action_name' : if name is qrcode_permanent_channel then 'QR_LIMIT_SCENE' else 'QR_SCENE'
        'action_info' : 'scene': 'scene_id': scene_id
      json.expire_seconds = qrcode_temporary_expires unless name is qrcode_permanent_channel
      request
        method : 'POST'
        url    : "#{api_common}/qrcode/create?access_token=#{access_token}"
        json   : json
      , (err, result) ->
        if err
          console.error err
          return res.send 500
        {body: {ticket}} = result
        key = "WX:TICKETS:#{ticket}"
        value = JSON.stringify [session, name, query]
        if name is qrcode_permanent_channel
          redis_client.set key, value
        else
          redis_client.setex key, 1800, value
        res.redirect "#{api_qrcode}/showqrcode?ticket=#{encodeURI(ticket)}"

    # + 永久二维码根据场景编号生成二维码；
    # + 临时二维码请求一个新的临时场景号，保证该号大于最大永久二维码号，
    #   便于在事件推送中根据`scene_id`判断类型。
    if name is qrcode_permanent_channel
      create query.scene_id
    else
      redis_client.incr 'WX:SCENE_ID', (err, scene_id) =>
        create scene_id + qrcode_permanent_maximum

  # ### 查询扫码结果
  router.get '/scan/:name?', (req, res) ->
    [session, name, query] = identify_qrcode req

    # 1. 根据关联参数生成检索键；
    # 2. 缓存微信服务器的`请求/响应`对；
    # 3. 标记该条码被桌面端监听，需由桌面端查询进程响应。
    id = JSON.stringify [session, name, query]
    if name is qrcode_permanent_channel
      unsent_dt_responses[id] ?= []
      unsent_dt_responses[id].push([req, res])
    else
      unsent_dt_responses[id] = [req, res]
      redis_client.setex "WX:SCAN:QUERY:#{id}", qrcode_long_poll_timeout, 1

    # `30`秒后，如果该条码仍未被扫描：
    #
    # 1. 从未响应的桌面请求缓存中删除；
    # 2. 发送`404`，通知桌面端重新查询。
    setTimeout ->
      return unless dt_res = unsent_dt_responses[id]
      if name is qrcode_permanent_channel
        if dt_res.some(([_req]) -> _req is req)
          unsent_dt_responses[id] = unsent_dt_responses[id].filter(([_req]) -> _req isnt req)
          delete unsent_dt_responses[id] unless unsent_dt_responses[id].length
          res.send 404
      else
        delete unsent_dt_responses[id] if dt_res[0] is req
        res.send 404
    , qrcode_long_poll_timeout * 1000

  # ### 伺服桌面端脚本
  router.get '/wx.js', (req, res) ->
    res.sendfile "#{__dirname}/wx_client.js"

  router.get '/ace/ace.js', (req, res) ->
    res.sendfile "#{__dirname}/ace/ace.js"

  router.get '/ace/mode-markdown.js', (req, res) ->
    res.sendfile "#{__dirname}/ace/mode-markdown.js"

  router.get '/ace/theme-terminal.js', (req, res) ->
    res.sendfile "#{__dirname}/ace/theme-terminal.js"

  # ### 编辑菜单页面占位符
  markdown_2_json_placeholder = 'function markdown_2_json() {}'

  # ### 渲染编辑菜单页面
  render_admin = (markdown) ->
    "#{fs.readFileSync("#{__dirname}/admin.html")}"
    .replace('MARKDOWN', markdown)
    .replace(markdown_2_json_placeholder, markdown_2_json.toString())
    .replace('APPSECRET', app_secret)

  # ### 访问管理员页面
  router.get '/admin', (req, res) ->
    res.sendfile "#{__dirname}/login.html"

  router.post '/admin', (req, res) ->
    # console.log req.body.app_secret, req.body.action
    if req.body.app_secret isnt app_secret
      res.send fs.readFileSync("#{__dirname}/login.html").toString().replace('ERROR', 'show')
    else if req.body.action is '开始管理'
      wx.get_menu (err, json) ->
        return res.send 500, err if err
        # console.log 'RENDER ADMIN'
        res.send render_admin json_2_markdown json
    else if req.body.action is '更新菜单'
      wx.create_menu markdown_2_json(req.body.buttons), (err) ->
        if err
          console.error err
          return res.send 500 if err
        wx.get_menu (err, json) ->
          if err
            console.error err
            return res.send 500 if err
          res.send render_admin json_2_markdown json

  # ### 接口验证中间件
  #
  # 该段之后，全部请求均来自微信服务器，验证该消息真伪性（该机制无法抵御回放攻击）。
  router.use ({query: {signature, timestamp, nonce}}, res, next) =>
    message = _([token, timestamp, nonce]).sort().join('')
    return next() if signature is crypto.createHash('sha1').update(message).digest('hex')
    res.send 401

  # ### 验证接口有效性
  router.get '/', ({query: {echostr}}, res) ->
    res.send echostr

  # ### 处理微信消息
  router.post '/', (req, res, next) =>

    # 1. 获取原始请求内容。
    getRawBody req,
      length   : req.headers['content-length']
      limit    : '1mb'
      encoding : 'utf8'

    , (err, string) =>
      return res.send 400 if err
      console.info string if debug

      # 2. 解析请求XML内容。
      xml2js.parseString string, (err, result) =>
        return res.send 400 if err

        # 3. 按消息内容增补请求对象。
        message = Object.keys(result.xml).reduce (memo, key) ->
          memo[_s.underscored(key)] = result.xml[key][0]
          memo
        , {}
        # console.log 'create_time', message.create_time
        message.msg_id ?= "#{message.from_user_name}@#{Date.now()}"

        # 4. 组装用户之后：
        process_message = (user) ->

          # 增补请求对象。
          _(req).extend(message)
          _(req.user ?= {}).extend(user)

          # 4. 令响应对象能够回复消息。
          _(res).extend(reply(req))

          # 关注或扫码事件均可触发扫码处理流程，故独立定义扫码处理流程。
          scan = (params) ->

            # 在确定条码`名称`与`查询`之后，
            # 判断是否有桌面端关注该条码被扫描事件。
            process_scan = ->
              id = JSON.stringify [session, name, query]

              # 

              # 永久二维码直接在微信响应进程处理。
              if name is qrcode_permanent_channel
                if scan_handler = @scan_handlers[name]

                    # + 用原始扫码消息增补请求对象。
                    # + 用传入消息的`user`键，增补请求对象的`user`键，并具备客服消息回复功能。
                    _(req).extend(message)
                    _(req.user ?= {}).extend(user, user_actions)

                    # 永久二维码的`scene_id`作为`params`供客户使用。
                    req.params.scene_id = query.scene_id
                    _(req.query).extend(query)

                    # 调用扫码处理句柄参数为：
                    #
                    # 1. `请求`对象：来自桌面端的原始查询请求；
                    # 2. `手机`对象：支持全部微信被动回复方法；
                    # 3. `桌面`回掉：模拟成桌面端注册回调方法。
                    mobile  = res
                    desktop_callback = -> redis_client.publish 'WX:SEND:DESKTOP', JSON.stringify id: id, content: [message.msg_id].concat Array::slice.call(arguments)
                    scan_handler req, mobile, desktop_callback

                # 未注册永久二维码处理流程时：
                # + 响应微信`200`
                # + 向全部关注的桌面端发送扫码用户。
                else
                  res.ok()
                  redis_client.publish 'WX:SEND:DESKTOP', JSON.stringify id: id, content: [message.msg_id, user]

              else redis_client.exists "WX:SCAN:QUERY:#{id}", (err, querying) =>
                # console.log '有无关注', id, querying

                # 如有桌面端关注，交由桌面端进程处理。
                if querying
                  redis_client.del "WX:SCAN:QUERY:#{id}"
                  redis_client.publish 'WX:SCAN:TEMPORARY', JSON.stringify id: id, user: user, content: message, msg_id: message.msg_id

                  # + 服务器端已注册处理句柄时，缓存微信端的请求。
                  # + 服务器端未注册处理句柄时，向微信端响应`OK`。
                  if @scan_handlers[name] then unsent_mb_responses[id] = res
                  else res.ok()

                # 无桌面端关注时，如已注册处理句柄，
                # 将二维码的查询参数增补至请求对象查询参数中，在当前进程内处理。
                else if scan_handler = @scan_handlers[name]
                  _(req.query).extend(query)
                  scan_handler(req, res, ->)

                # 未注册处理句柄时，向微信端响应`OK`。
                else res.ok()

            # 如已传入参数，解构后，直接处理扫描事件。
            if params
              [session, name, query] = params
              process_scan()

            # 如未传入参数，查询后，处理扫描事件：
            # 找不到对应票据时，根据场景编号确定二维码种类，临时二维码，无对应票据时，无法处理，直接响应`200`。
            else redis_client.get "WX:TICKETS:#{message.ticket}", (err, result) =>
              # console.log 'T', 1 <= (scene_id = message.event_key.match(/\d+/)[0]) <= qrcode_permanent_maximum
              if result
                [session, name, query] = JSON.parse "#{result}"
              else if 1 <= (scene_id = message.event_key.match(/\d+/)[0]) <= qrcode_permanent_maximum
                session = ''
                name    = qrcode_permanent_channel
                query   = scene_id: +scene_id
              else return res.ok()
              process_scan()

          # 5. 判断接收到消息类型。
          switch msg_type = req.msg_type.toLowerCase()

            # 收到文本消息时，如注册了文本处理句柄，使用该句柄处理，否则响应`200`。
            when 'text'
              for [pattern, text_handler] in @text_handlers
                if (typeof pattern is 'string' and message.content.trim() is pattern) or (typeof pattern is 'object' and match = message.content.match(pattern))
                  _(req.params).extend(match)
                  text_handler(req, res)
                  handled = on
                  break
              res.ok() unless handled

            # 收到图片、语音、视频、地理位置、链接时，如注册了处理句柄，使用该句柄处理：
            when 'image', 'voice', 'video', 'location', 'link'
              if handler = @["#{msg_type}_handler"] then handler req, res
              else res.ok()

            # 收到事件消息时，判断事件类型：
            when 'event'
              switch req.event.toLowerCase()

                # 订阅时：
                when 'subscribe'

                  # 1. 优先由扫码句柄处理，扫码句柄无法处理时；
                  # 2. 退化至订阅句柄处理；
                  # 3. 无订阅句柄时发`OK`。
                  subscribe = ->
                    if @subscribe_handler
                      @subscribe_handler req, res
                    else res.ok()

                  # 收到订阅消息时，如果由扫码产生，并且有对应名称二维码的处理句柄，
                  # 使用二维码处理句柄处理，否则，使用订阅处理句柄处理。
                  return subscribe() unless message.ticket
                  redis_client.get "WX:TICKETS:#{message.ticket}", (err, result) =>
                    if result
                      [session, name, query] = JSON.parse "#{result}"
                    else if 1 <= (scene_id = message.event_key.match(/\d+/)[0]) <= qrcode_permanent_maximum
                      session = ''
                      name    = qrcode_permanent_channel
                      query   = scene_id: +scene_id
                    else return subscribe()

                    # + 已注册扫码句柄，使用扫码句柄处理；
                    # + 未注册扫码句柄：
                    #
                    #   1. 使用订阅流程处理；
                    #   2. 向桌面端发送用户。
                    if @scan_handlers[name]
                      scan [session, name, query]

                    # 未定义对应扫码处理流程时：
                    # + 用关注处理流程处理；
                    # + 向关注客户端发送扫码用户。
                    else
                      subscribe()
                      redis_client.publish 'WX:SEND:DESKTOP', JSON.stringify id: JSON.stringify([session, name, query]), content: [message.msg_id, user]

                # 取消订阅时：
                #
                # + 如注册了取消订阅处理句柄，使用该句柄处理；
                # + 否则响应`200`。
                when 'unsubscribe'
                  if @unsubscribe_handler
                    @unsubscribe_handler req, res
                  else res.ok()

                # 收到点击按钮消息时，
                when 'click'
                  if click_handler = @click_handlers[req.event_key]
                    click_handler(req, res)
                  else res.ok()

                # 如为二维码扫描事件，
                when 'scan' then scan()
                
                # 尚无法处理的事件，直接响应`200`。
                else res.ok()

        # 默认配置下，调用微信接口组装用户信息。
        if populate_user and message.event?.toLowerCase() not in ['unsubscribe']
          wx.user message.from_user_name, (err, user) ->
            if err
              console.error err
              return res.send 500
            process_message user

        # 禁用自动组装时，用仅带编号的用户替代。
        else
          process_message wx.user message.from_user_name

  # ### 媒体标识符格式
  regex_media_id = /^[\w\_\-]{64}$/

  # ### 被动回复消息
  #
  # + 模拟被动回复（桌面端伺服进程发起）
  # + 真实被动回复（微信端伺服进程发起）
  reply = (req, id) ->
  
    # ### 模拟被动回复
    #
    # 通过`REDIS`中继，由桌面端伺服进程，模拟向微信同步回复消息。
    if id
      return ['text', 'image', 'voice', 'video', 'music', 'news', 'transfer', 'ok']
      .reduce (memo, type) ->
        memo[type] = (content) ->
          redis_client.publish 'WX:SEND:MOBILE', JSON.stringify
            id      : id
            type    : type
            content : content
        memo
      , {}
  
    # ### 真实被动回复
    #
    # 消息通用部分：
    #
    # + 发送方用户名；
    # + 接收方用户名；
    # + 消息创建时间。
    message = (message) ->
      "<xml>
      <ToUserName><![CDATA[#{req.from_user_name}]]></ToUserName>
      <FromUserName><![CDATA[#{req.to_user_name}]]></FromUserName>
      <CreateTime>#{~~(Date.now() / 1000)}</CreateTime>
      #{message}
      </xml>"
  
    # ### 回复文本
    text: (text) ->
      @send message "<MsgType><![CDATA[text]]></MsgType>
        <Content><![CDATA[#{text}]]></Content>"

    # ### 回复图片
    image: (image) ->
      send = (image) =>
        @send message "<MsgType><![CDATA[image]]></MsgType>
          <Image><MediaId><![CDATA[#{image}]]></MediaId></Image>"

      if image.match(regex_media_id)
        send image
      else
        wx.upload 'image', image, (err, res) =>
          if image = res?.media_id
            send image
          else
            console.error err or res
            @send 500

    # ### 回复语音
    voice: (voice) ->
      send = (voice) =>
        @send message "<MsgType><![CDATA[voice]]></MsgType>
          <Voice><MediaId><![CDATA[#{voice}]]></MediaId></Voice>"

      if voice.match(regex_media_id)
        send voice
      else
        wx.upload 'voice', voice, (err, res) =>
          return @send 500 unless voice = res?.media_id
          send voice
    
    # ### 回复视频
    video: (video) ->
      send = ({video, title, description}) =>
        @send message "<MsgType><![CDATA[video]]></MsgType>
          <Video>
          <MediaId><![CDATA[#{video}]]></MediaId>
          <Title><![CDATA[#{title}]]></Title>
          <Description><![CDATA[#{description}]]></Description>
          </Video>"

      if video.video.match(regex_media_id)
        send video
      else
        wx.upload 'video', video.video, (err, res) =>
          return @send 500 unless video.video = res?.media_id
          send video

    # ### 回复音乐
    music: (music) ->
      send = ({title, description, music_url, hq_music_url, thumb_media}) =>
        @send message "<MsgType><![CDATA[music]]></MsgType>
          <Music>
          <Title><![CDATA[#{title}]]></Title>
          <Description><![CDATA[#{description}]]></Description>
          <MusicUrl><![CDATA[#{music_url}]]></MusicUrl>
          <HQMusicUrl><![CDATA[#{hq_music_url}]]></HQMusicUrl>
          <ThumbMediaId><![CDATA[#{thumb_media}]]></ThumbMediaId>
          </Music>"

      if music.thumb_media.match(regex_media_id)
        send music
      else
        wx.upload 'thumb', music.thumb_media, (err, res) =>
          return @send 500 unless music.thumb_media = res?.thumb_media_id
          send music
  
    # 新闻类型另含：
    #
    # + 消息类型；
    # + 新闻条数；
    # + 新闻内容。
    news: (articles) ->
  
      articles = [].concat(articles).map ({title, description, pic_url, url}) ->
        "<item>
        <Title><![CDATA[#{title}]]></Title> 
        <Description><![CDATA[#{description}]]></Description>
        <PicUrl><![CDATA[#{pic_url}]]></PicUrl>
        <Url><![CDATA[#{url}]]></Url>
        </item>"
      
      @send message "<MsgType><![CDATA[news]]></MsgType>
        <ArticleCount>#{articles.length}</ArticleCount>
        <Articles>#{articles.join('')}</Articles>"
  
    # 转移客服接口
    transfer: ->
      @send message "<MsgType><![CDATA[transfer_customer_service]]></MsgType>"

    # 不发送任何消息，仅响应`200`。
    ok: -> @send 200

  # ### 客服消息
  user_actions =

    # ### 不同尺寸
    image_url: (size) ->
      return null unless @headimgurl
      @headimgurl.replace(/\/0$/i, "/#{size}")

    # ### 客服消息：文本
    text: (text, callback) ->
      request
        method : 'POST'
        url    : "#{api_common}/message/custom/send?access_token=#{access_token}"
        json   :
          touser  : @openid
          msgtype : 'text'
          text    : content: text
      , wrap callback

    # ### 客服消息：图片
    image: (image, callback) ->
      send = (image) =>
        request
          method : 'POST'
          url    : "#{api_common}/message/custom/send?access_token=#{access_token}"
          json   :
            touser  : @openid
            msgtype : 'image'
            image   : media_id: image
        , wrap callback

      if image.match(regex_media_id)
        send image
      else
        wx.upload 'image', image, (err, res) ->
          return callback? err or res unless image = res?.media_id
          send image

    # ### 客服消息：语音
    voice: (voice, callback) ->
      send = (voice) =>
        request
          method : 'POST'
          url    : "#{api_common}/message/custom/send?access_token=#{access_token}"
          json   :
            touser  : @openid
            msgtype : 'voice'
            voice   : media_id: voice
        , wrap callback

      if voice.match(regex_media_id)
        send voice
      else
        wx.upload 'voice', voice, (err, res) ->
          return callback? err or res unless voice = res?.media_id
          send voice

    # ### 客服消息：视频
    video: (video, callback) ->
      send = ({title, description, video}) =>
        request
          method : 'POST'
          url    : "#{api_common}/message/custom/send?access_token=#{access_token}"
          json   :
            touser  : @openid
            msgtype : 'video'
            video   :
              title       : title
              description : description
              media_id    : video
        , wrap callback
      if video.video.match regex_media_id
        send video
      else
        wx.upload 'video', video.video, (err, res) ->
          return callback? err or res unless video.video = res?.media_id
          send video

    # ### 客服消息：音乐
    music: (music, callback) ->
      send = ({title, description, music_url, hq_music_url, thumb_media}) =>
        request
          method : 'POST'
          url    : "#{api_common}/message/custom/send?access_token=#{access_token}"
          json   :
            touser  : @openid
            msgtype : 'music'
            music   :
              title          : title
              description    : description
              musicurl       : music_url
              hqmusicurl     : hq_music_url
              thumb_media_id : thumb_media
        , wrap callback

      if music.thumb_media.match(regex_media_id)
        send music
      else
        wx.upload 'thumb', music.thumb_media, (err, res) ->
          return callback? err or res unless music.thumb_media = res?.thumb_media_id
          send music

    # ### 客服消息：图文
    news: (news, callback) ->
      request
        method : 'POST'
        url    : "#{api_common}/message/custom/send?access_token=#{access_token}"
        json   :
          touser  : @openid
          msgtype : 'news'
          news    : articles: news.map ({title, description, pic_url, url}) ->
            title       : title
            description : description
            picurl      : pic_url
            url         : url
      , wrap callback

  # ### 与反`REST`设计战斗
  wrap = (callback = ->) ->
    (err, res) ->
      return callback err or res.body if err or res.body?.errcode
      callback null, res.body

  # ### `markdown`菜单转微信
  wx.markdown_2_json = markdown_2_json = (markdown) ->
    parse = (line) ->
      if match = line.match /\[(.*)\]\((.*)\)/
        type : 'view'
        name : match[1]
        url  : match[2]
      else if match = line.match /\[(.*)\]\((.*)/
        type : 'click'
        name : match[1]
        key  : match[1]
      else
        type : 'click'
        name : line
        key  : line
    buttons = []
    for line in markdown.split /\n/
      line = line.trim()
      if match = line.match /^[\+\＋](.+)/
        buttons.push parse match[1].trim()
      else if match = line.match /^[\-\－](.+)/
        sub_buttons = buttons[buttons.length - 1].sub_button ?= []
        sub_buttons.push parse match[1].trim()
    json = buttons

  # ### 微信菜单转`markdown`
  json_2_markdown = (json) ->
    markdown = ''
    for button in buttons = json
      if button.sub_button?.length
        markdown += "+ #{button.name}\n"
        for sub_button in button.sub_button
          if sub_button.type in ['view']
            markdown += "  - [#{sub_button.name}](#{sub_button.url})\n"
          else
            markdown += "  - #{sub_button.name}\n"
      else if button.type in ['view']
        markdown += "+ [#{button.name}](#{button.url})\n"
      else
        markdown += "+ #{button.name}\n"
    markdown

  # ### 注册消息处理句柄
  _.extend router,

    # ### 注册文本消息处理句柄
    text: (pattern, handler) =>
      if typeof pattern in ['function']
        handler = pattern
        pattern = /.*/
      @text_handlers.push [pattern, handler]
      @

    # ### 注册图片消息处理句柄
    image: (@image_handler) => @

    # ### 注册语音消息处理句柄
    voice: (@voice_handler) => @

    # ### 注册视频消息处理句柄
    video: (@video_handler) => @

    # ### 注册地理位置处理句柄
    location: (@location_handler) => @

    # ### 注册链接处理句柄
    link: (@link_handler) => @

    # ### 注册关注与取消关注处理句柄
    subscribe   : (@subscribe_handler) => @
    unsubscribe : (@unsubscribe_handler) => @

    # ### 注册点击菜单按钮处理句柄
    click: (key, handler) =>
      @click_handlers[key] = handler
      @

    # ### 注册二维码处理句柄
    scan: (channel, handler) =>
      if typeof channel is 'function'
        handler = channel
        channel = ''
      @scan_handlers[channel.toLowerCase()] = handler
      @

    # ### 检索用户基本信息
    #
    # + 传入回调函数时，通过微信`API`检索用户基本信息，
    # + 不传回调函数时，仅仅创建一个可以进行客服消息回复的空对象（包含`openid`）。
    user: (openid, callback) =>
      if callback
        request
          method : 'GET'
          url    : "#{api_common}/user/info?access_token=#{access_token}&openid=#{openid}"
          json   : on
        , (err, res) ->
          return callback err or res.body if err or res.body.errcode
          callback null, _(res.body).extend(user_actions)
        @
      else _(openid: openid).extend(user_actions)

    # ### 文件上传
    #
    # 直接调用`curl`命令，完成文件上传。
    upload: (type, media, callback = ->) =>
      exec "curl -F media=@#{media} \"#{api_binary}/media/upload?access_token=#{access_token}&type=#{type}\"", (err, res) ->
        return callback err if err
        try
          res = JSON.parse res
        catch err
          return callback err
        return callback res if res.errcode
        callback null, res
      @

    # ### 文件下载
    download: (media_id, callback = ->) =>
      request
        url      : "#{api_binary}/media/get?access_token=#{access_token}&media_id=#{media_id}"
        encoding : null
      , (err, res) ->
        return callback err if err
        callback null, res.body

    # ### 获取按钮
    get_menu: (callback = ->) ->
      request
        method : 'GET'
        url    : "#{api_common}/menu/get?access_token=#{access_token}"
        json   : on
      , (err, res) ->
        return callback err or res.body if err or res.body.errcode not in [undefined, 46003]
        callback null, res.body.menu?.button or []
      @

    # ### 创建按钮
    create_menu: (buttons, callback) ->
      request
        method : 'POST'
        url    : "#{api_common}/menu/create?access_token=#{access_token}"
        json   : button: buttons
      , wrap callback
      @

    # ### 删除按钮
    delete_menu: (callback) ->
      request
        method : 'GET'
        url    : "#{api_common}/menu/delete?access_token=#{access_token}"
        json   : on
      , wrap callback
      @

    # ### 关注者列表
    subscribers: (next_openid, callback) ->
      if typeof next_openid is 'function'
        callback = next_openid
        next_openid = null
      request
        method : 'GET'
        url    : "#{api_common}/user/get?access_token=#{access_token}#{if next_openid then "&next_openid=#{next_openid}" else ''}"
        json   : on
      , wrap callback
      @

    # ### 组装后的关注者列表
    populate_subscribers: (start, end, callback) ->

      # 根据结束位置决定从微信拉取次数：
      index = ~~ (end / 10000) + 1

      # 先拉取关注者`openid`。
      next_openid = null
      total = null
      index_tasks = [0..index].map ->
        (callback) ->
          _callback = (err, res) ->
            if err
              console.error err
              return callback err
            next_openid = res.data.next_openid
            total = res.total
            callback null, res
          request
            method : 'GET'
            url    : "#{api_common}/user/get?access_token=#{access_token}#{if next_openid then "&next_openid=#{next_openid}" else ''}"
            json   : on
          , wrap _callback

      # 再组装完整关注者信息。
      async.series index_tasks, (err, res) ->
        if err
          console.error err
          return callback err
        tasks = res.reduce(((memo, {data: {openid}}) -> memo.concat(openid)), [])[start..end]
        .map((openid) -> (callback) -> wx.user(openid, callback))
        async.parallelLimit tasks, 5, (err, res) ->
          if err
            console.error err
            return callback err
          callback null,
            total       : total
            subscribers : res
