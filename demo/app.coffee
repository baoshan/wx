cluster = require 'cluster'

# ## 集群主进程
if cluster.isMaster
  numCPUs = require('os').cpus().length
  cluster.fork() for i in [0...numCPUs]

# ## 集群辅进程
else

  # ### 依赖模组
  fs           = require('fs')
  path         = require('path')
  express      = require('express')
  favicon      = require('static-favicon')
  logger       = require('morgan')
  session      = require('express-session')
  RedisStore   = require('connect-redis')(session)
  cookieParser = require('cookie-parser')
  bodyParser   = require('body-parser')


  # ### 代码转译
  require('jade').filters.escape = (block) ->
    block
    .replace(/&/g,  '&amp;' )
    .replace(/</g,  '&lt;'  )
    .replace(/>/g,  '&gt;'  )
    .replace(/"/g,  '&quot;')
    .replace(/#/g,  '&#35;' )
    .replace(/\\/g, '\\\\'  )

  # ### 应用程序配置
  app = express()

  app.set 'views', path.join(__dirname, 'views')
  app.set 'view engine', 'jade'
  app.use favicon()
  app.use logger 'dev'
  app.use bodyParser.json()
  app.use bodyParser.urlencoded()
  app.use cookieParser()
  app.use session
    store  : new RedisStore()
    secret : 'keyboard cat'
    key    : 'sid'
  app.use express.static(path.join(__dirname, 'public'))

  # ### 安装与使用
  wx = global.wx = new require('wx') \
    require(path.join(__dirname, 'wx_secret.coffee'))

  # ### 
  subscribers = null
  exports.subscribers = ->
    subscribers or []

  setTimeout ->

    # ### SUBSCRIBERS
    wx.subscribers (err, res) ->
      console.log res if res

      # ### 确定起始索引
      return unless res
      from = Math.max (res.total - 101), 0
      to = res.total - 1

      # ### POPULATE_SUBSCRIBERS
      wx.populate_subscribers from, to, (err, res) ->
        {total, subscribers} = res if res

  # ### 启动延迟
  , 2000

  app.use '/wx', wx

  # ### 首页
  index        = require('./routes/index')
  app.use '/', index

  # ### MESSAGE_TEXT
  wx.text '文本', (req, res) ->
    res.text '北京，晴[太阳]'

  # ### MESSAGE_IMAGE
  wx.text '图片', (req, res) ->
    res.image 'image.jpg'

  # ### MESSAGE_VOICE
  wx.voice (req, res) ->
    res.voice req.media_id

  # ### RECEIVE_IMAGE
  wx.image (req, res) ->
    res.image req.media_id

  # ### RECEIVE_VIDEO
  wx.video (req, res) ->
    res.video
      title       : '视频标题'
      description : '视频描述'
      video       : 'video.mp4'

  # ### RECEIVE_LOCATION
  wx.location (req, res) ->
    coordinate = req.location_x + ',' + req.location_y
    res.text "您在#{req.label or coordinate}"

  # ### MESSAGE_VIDEO
  wx.text '视频', (req, res) ->
    video =
      title       : '视频标题'
      description : '视频描述'
      video       : 'video.mp4'
    res.ok()
    req.user.video video

  # ### MESSAGE_MUSIC
  wx.text '音乐', (req, res) ->
    music =
      title        : '音乐标题'
      description  : '音乐描述'
      music_url    : 'http://182.92.129.185/music.mp3'
      hq_music_url : 'http://182.92.129.185/music.mp3'
      thumb_media  : 'cover.jpg'
    res.music music

  # ### MESSAGE_NEWS
  wx.text '图文', (req, res) ->
    news = [
      title       : '头条新闻标题'
      description : '头条新闻描述'
      pic_url     : ''
      url         : ''
    ,
      title       : '次条新闻标题'
      description : '次条新闻描述'
      pic_url     : ''
      url         : ''
    ]
    res.news news

  # ### SEND_TRANSFER
  wx.text /客服.*/, (req, res) ->
    res.transfer()

  # ##  接收消息

  # ### TEXT_PATTERN
  wx.text /(.+)天气/, (req, res) ->
    res.text "#{req.params[1]}，晴[太阳]"

  # ### TEXT_CONSTANT
  wx.text '你好', (req, res) ->
    res.text "#{req.user.nickname}，么么哒"

  # ### NEW_USER_TEXT
  wx.text '构造用户对象回复文本', (req, res) ->
    res.ok()
    wx.user(req.from_user_name).text('创建用户：')
    wx.user req.from_user_name, (err, user) ->
      user.text "#{user.nickname}，并回复文本"

  # ### TEXT_ALL
  wx.text (req, res) ->
    res.text "#{req.content}，喵呜~"

  # ### RECEIVE_LINK
  wx.link (req, res) ->
    res.text "《#{req.title}》一文发人深省…"

  # ### QRCODE_HOME
  wx.scan 'home', (req, res, callback) ->
    res.text '欢迎探索微信应用框架[微笑]'
    callback()

  # ### QRCODE_TEMPORARY
  wx.scan 'fruits', (req, res, desktop_callback) ->
    res.text "#{req.user.nickname}偷吃了#{req.query.name}"
    desktop_callback '吃一口'

  # ### QRCODE_PERMANENT
  wx.scan 'permanent', (req, res, callback) ->
    {nickname} = req.user
    {from} = req.query
    {scene_id} = req.params
    res.text "#{nickname}扫描#{from}编号#{scene_id}的永久二维码"
    callback req.user

  # ### QRCODE_LOGIN
  wx.scan (req, res, desktop_callback) ->
    req.session.user = req.user
    res.text "#{req.user.nickname}从#{req.query.from}登录"
    desktop_callback req.user

  # ### CLICK_BUTTON
  wx.click '点击按钮', (req, res) ->
    res.text "被#{req.user.nickname}点了一下[害羞]"

  # ### CLICK_BUTTON_SECOND_LEVEL
  wx.click '拉取信息', (req, res) ->
    res.text "#{req.user.nickname}成功拉取信息。"

  # ### SUBSCRIBE
  wx.subscribe (req, res) ->
    nickname = req.user.nickname
    res.text "[礼物]欢迎#{nickname}关注微信应用框架！"

  # ### UNSUBSCRIBE
  wx.unsubscribe (req, res) ->
    # 按具体需求进行处理。
    res.ok()

  # ### 404
  app.use (req, res, next) ->
    err = new Error("Not Found")
    err.status = 404
    next err

  # ### 研发环境异常处理
  if app.get('env') is 'development'
    app.use (err, req, res, next) ->
      res.status err.status or 500
      res.render 'error',
        message: err.message
        error: err

  # ### 部署环境异常处理
  app.use (err, req, res, next) ->
    res.status err.status or 500
    res.render 'error',
      message: err.message
      error: {}

  # ### 监听端口
  app.set 'port', process.env.PORT or 3000

  # ### 启动
  server = app.listen app.get('port'), ->
    console.log 'Express server listening on port ' + server.address().port
