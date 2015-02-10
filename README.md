## [WeiXin]

(minimalist) WeChat Middleware for Express.js

## 微信应用框架

`wx`是极简设计的微信（公共平台）应用参考级框架，而并非微信接口在`node.js`下的幂等映射。


[WeiXin]: http://weixinjs.org/


## 安装
`wx`要求在线的**[Redis]**实例。默认情况下，`wx`尝试连接本地实例，您可以指定`Redis`连接。利用`Redis`，`wx`具备：

+ 集群模式下自动管理微信令牌；
+ 浏览器端捕捉二维码扫描；
+ 等功能。

[Redis]:http://redis.io

===
1. ```npm install wx```

2. ☞ 登录**[微信公众平台]**    
   ☞ 高级功能    
   ☞ 开发模式，获取token
   
   [微信公众平台]: https://mp.weixin.qq.com 
   
    *配置服务器时仅token必须。  
      
3. 服务器端

  ```coffeescript
   app = express()    
   wx  = new require 'wx'
     token            : 'xxx-xx-xx'
     app_id           : 'xx-xxx'
     app_secret       : 'xxxxxxxxxxxx'
     encoding_aes_key : 'xxxxxx'
   app.use '/wx', wx
   ```
4.  启动应用程序后，修改微信开发模式中服务器配置为：`http://server.address/wx`，且有与程序相一致的`token`。

## 接受文本消息

通过`wx.text`注册文本消息处理流程：  
 
   +  `req.content`为用户所发文本；  
   +  `req.user`包含**[用户基本信息]**  

[用户基本信息]:http://mp.weixin.qq.com/wiki/index.php?title=获取用户基本信息  

探索几种根据用户发送文本，通过`res.text`被动回复的方式：  

**匹配正则表达式**    

```
wx.text /(.+)天气/, (req, res) ->
  res.text "#{req.params[1]}，晴[太阳]"
```
**接收文本常量**    

```
wx.text '你好', (req, res) ->
  res.text "#{req.user.nickname}，么么哒"
```
**接收任意文本**    

```
wx.text (req, res) ->
  res.text "#{req.content}，喵呜~"
```
*`wx`按注册顺序匹配消息，最后注册接收任意文本句柄。

## 接受其他消息

###  图片
下面演示了通过`wx.image`接收用户发送图片，再以`res.image`被动回复相同图片的方式：

```
wx.img, (req, res) ->
  res.image req.media_id
```
可以通过`wx.download`下载图片，得到图片`buffer`:

```
wx.download req.media_id, (err, image) ->
```
*`res.image`亦接收图片文件路径，自动上传图片（为避免请求超时，建议预传图片，或先`ok`再发送客服图片消息）。

### 语音
下面演示了通过`wx.voice`接收用户发送图片，再以`res.voice`被动回复相同语音的方式：

```
wx.voice, (req, res) ->
  res.voice req.media_id
```
可以通过`wx.download`下载图片，得到语音`buffer`:

```
wx.download req.media_id, (err, voice) ->
```
*`res.voice`亦接收语音文件路径，自动上传语音（为避免请求超时，建议预传语音，或先`ok`再发送客服语音消息）。

### 视频
下面演示了通过`wx.video`接收用户发送图片，再以`res.video`被动回复视频文件的方式：

```
wx.video, (req, res) ->
  res.video
    title        : '视频标题'
    description  : '视频描述'
    video        : 'video.mp4'
```

### 地理位置
下面演示了通过`wx.location`接收用户发送的地理位置，通过`req.label`、`req.location_y`、`req.location_x`获取地址、维度、经度的方式：

```
wx.location, (req, res) ->
  coordinate = req.location_x + ',' + req.location_y
  res.text "您在#{req.label or coordinate}"
```

### 链接
下面演示了通过`wx.link`接收用户发送链接，再通过`req.title`、`req.description`、`req.url`获取标题、描述与链接的方式：

```
wx.link, (req, res) ->
  res.text "《#{req.title}》一文发人深省…"
```
##  发送消息

###  文本
**被动回复文本消息：**

```
wx.text '文本', (req, res) ->
  res.text '北京，晴[太阳]'
```
5秒内无法应答时，先`200`，再通过`req.user`发送客服文本消息（避免微信服务器发起重试）：

```
wx.text '文本', (req, res) ->
  res.ok()
    req.user.text '北京，晴[太阳]'
```
**主动发送客服文本消息：**

```
wx.user('xx_xxx').text('北京，晴[太阳]')
```

###  图片
**被动回复图片消息：**

使用`res.image`被动回复图片。既可指定本地文件路径，由`wx`自动上传图片；亦可直接传入有效的`media_id`，省略上传图片步骤。

```
wx.image, (req, res) ->
   res.image req.media_id
```
如需上传图片，建议先`200`，再通过`req.user`发送客服消息，以免因上传耗时超5秒导致重试。

```
wx.img, (req, res) ->
  res.ok()
    req.user.image 'image.jpg'
```
上传图片获取`media_id`方式为：

```
wx.upload 'image', 'image.jpg', (req, res) ->
  # res.media_id 是上传图片的 media_id
```
**主动发送客服图片消息：**

```
wx.user('xx_xxx').image('image.jpg')
```

###  语音
**被动回复语音消息：**

使用`res.voice`被动回复语音。既可指定本地文件路径，由`wx`自动上传语音；亦可直接传入有效的`media_id`，省略上传语音步骤。

```
wx.voice, (req, res) ->
   res.voice req.media_id
```
如需上传语音，建议先`200`，再通过`req.user`发送客服消息，以免因上传耗时超5秒导致重试。

```
wx.voice, (req, res) ->
  res.ok()
    req.user.image 'voice.amr'
```
上传图片获取`media_id`方式为：

```
wx.upload 'voice', 'voice.amr', (req, res) ->
  # res.media_id 是可以重用的语音 media_id
```
**主动发送客服语音消息：**

```
wx.user('xx_xxx').voice('image.jpg')
```

###  视频
**被动发送视频消息：**

使用`res.video`被动回复视频。既可指定本地文件路径，由`wx`自动上传语音；亦可直接传入有效的`media_id`，省略上传视频步骤。

```
wx.video, (req, res) ->
  res.video
    title        : '视频标题'
    description  : '视频描述'
    video        : 'video.mp4'
```
如需上传视频，建议先`200`，再通过`req.user`发送客服消息，以免因上传耗时超5秒导致重试。

```
wx.video, (req, res) ->
  res.ok()
    req.user.video ...
```
上传视频获取`media_id`方式为：

```
wx.upload 'video', 'video.mp4', (req, res) ->
  # res.media_id 是可以重用的视频 media_id
```
**主动发送视频消息：**

```
wx.user('xx_xxx').video ...
```

###  音乐
**被动发送音乐消息：**

需上传专辑图片时，先`200`，再通过`req.user.music`发送客服音乐消息（避免上传耗时超5秒，微信服务器发起重试）：

```
wx.text '音乐', (req, res) ->
  music =
    title        : '音乐标题'
    description  : '音乐描述'
    music_url    : 'http://weixinjs.org/music.mp3'
    hq_music_url : 'http://weixinjs.org/music.mp3'
    thumb_media  : 'cover.jpg'
  res.music music
```
无客服消息权限，或已知专辑封面`thumb_media_id`时，可直接回复音乐：

```
wx.text '音乐', (req, res) ->
  res.music music
```
上传缩略图获取`media_id`方式为：

```
wx.upload 'thumb', 'cover.jpg', (req, res) ->
  # res.thumb_media_id 是可以重用的缩略图 thumb_media_id

```
**主动发送视频消息：** 请举一反三

###  图文
**被动发送图文消息：**

```
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
```
亦可通过req.user发送客服新闻消息

```
wx.text '新闻', (req, res) ->
  res.ok()
  req.user.news news
```
**主动发送图文消息：** 举一反三

###  转客服
**消息转多客服：**

通过`res.transfer`方法，将消息转发到多客服：

```
wx.text /客服.*/, (req, res) ->
  res.transfer()
```
*[公共平台开发者文档]有更多关于多客服的开发者资料。在[多客服]网站下载客户端。

[公共平台开发者文档]:http://mp.weixin.qq.com
[多客服]:http://dkf.qq.com

##  点击按钮

响应按钮点击，我们努力迫近最为自然的方式：   
使用`wx.click`方法，指定被点击按钮名称，即可捕捉该按钮点击事件。

```
wx.click '点击按钮', (req, res) ->
   res.text "被#{req.user.nickname}点了一下[害羞]"
```

##  编辑按钮

编辑菜单是一种内容创意，应当由`markdown`来完成。使用`wx`，你可以立即预览菜单效果，无需关注更多。安装`wx`后，可以通过`http://server.address/wx/admin`地址进入管理界面.

通过以下Markdown格式的文件可以编辑并实时预览按钮。

```
+ 点击按钮 
+ [链接文档](http://mp.weixin.qq.com/wiki) 
+ 二级菜单
   - [链接跳转](http://github.com/baoshan/wx)
   - 拉取信息
```



##  扫描二维码登录
**服务器端**

通过`wx.scan`注册扫码处理流程*。响应句柄参数分别为：

1.  浏览器请求，包含`req.session`会话、`req.user`微信用户、`req.query`二维码参数；
2.  微信响应，可被动回复各种消息；
3.  浏览器回调方法，可向浏览器发送任意数据。

```
wx.scan (req, res, desktop_callback) ->
  req.session.user = req.user
  res.text "#{req.user.nickname}从#{req.query.from}登录"
  desktop_callback req.user
```
**标记语言***

```
    <script src="/wx/wx.js"></script>     
    <img id="登录二维码" src="/wx/qrcode?from=网页" />
```
**浏览器端**

```
$('#登录二维码').scan (user) -> 
  {headimgurl: src, nickname: title} = user
  $img = $ "<img src='#{src}' /><p>#{title}</p>"
  $(@).replaceWith($img)
```
*建议为所有二维码指定名称进行分类，见临时二维码与永久二维码部分。

##  临时二维码
指定名称，可为二维码分类。下面二维码名称为`fruits`：

```
    <script src="/wx/wx.js"></script>     
    <img src="/wx/qrcode/fruits?name=cherry" />
```
*`wx`自动为被扫描的二维码增加`scanned`类名。

服务器端在`wx.scan`中指定二维码名称，注册该类二维码的处理流程。

```
wx.scan 'fruits', (req, res, desktop_callback) ->
  res.text "#{req.user.nickname}偷吃了#{req.query.name}"
  desktop_callback '吃一口'
```
##  永久二维码
*永久二维码图案稳定，永不过期，适于印刷品、广告等，实现来源统计用途。
名称在`1`－`100000`间为永久二维码，`[continuous]`条码支持连续扫描：

**服务器端**

通过`permanent`名称注册永久二维码扫码处理流程，用`req.params.scene_id`获取编号。

```
wx.scan 'permanent', (req, res, callback) ->
  {nickname} = req.user
  {from} = req.query
  {scene_id} = req.params
  res.text "#{nickname}扫描#{from}编号#{scene_id}的永久二维码"
  callback req.user
```
**浏览器端**

通过`scan`方法，捕捉永久二维码扫描事件

```
$('#永久二维码').scan ({nickname: title, headimgurl: src}) ->
  $img = $("<img src='#{src}' title='#{title}' />")
  $('#div_headimgs').append($img)
  $img.load -> $(@).addClass('loaded')
```

##  关注与取消关注
**关注**

通过`wx.subscribe`注册关注事件。

```
wx.subscribe (req, res) ->
  nickname = req.user.nickname
  res.text "[礼物]欢迎#{nickname}关注微信应用框架！"
```
*当用户通过扫描二维码关注时，如已注册相应的二维码扫码处理流程，则交给该流程处理，不触发`subscribe`事件，仍可根据`scan`事件的`req.event`为`subscribe`判断用户为通过扫码关注。

**取消关注**

通过`wx.unsubscribe`注册取消关注事件。

```
wx.unsubscribe (req, res) ->
  # 按具体需求进行处理。
  res.ok()
```

##  获取关注者列表
通过`wx.subscribers`方法，拉取关注者列表：

```
wx.subscribers (err, res) ->
  console.log res if res
```
获取到的关注者列表结构：

```
{
  "total" : 23000,
  "count" : 10000,
  "data"  : {"openid": ["OPENID1", ...]},
  "next_openid": "NEXT_OPENID"
}
```
亦可指定`next_openid`，拉取后续用户列表：

```
wx.subscribers next_openid, (err, res) ->
```
###  更多时候……

可以考虑用`wx.populate_subscribers`获取指定范围内关注者完整信息（分页显示关注用户、批量发送客服消息等）。

```
wx.populate_subscribers from, to, (err, res) ->
  {total, subscribers} = res if res
```
获取到的指定范围关注者完整信息结构：

```
{
  total       : 23000,
  subscribers : [{
    "subscribe"      : 1,
    "openid"         : "......",
    "nickname"       : "Band",
    "sex"            : 1,
    "language"       : "zh_CN",
    "city"           : "广州",
    "province"       : "广东",
    "country"        : "中国",
    "headimgurl"     : "http://wx.qlogo.cn/...",
    "subscribe_time" : 1382694957
  }, ...]
}
```

## 有限状态机

定义用户所处状态与各状态间跃迁条件，微信应用框架帮助您分解复杂业务，且毫不妥协研发体验：

```
wx.click '申办', (req, res) ->
  res.text '回复“固话”申办固话，回复“宽带”申办宽带。'
  req.user.state '申办'
  
wx.state('申办').text '固话', (req, res) ->
  req.text '正在为您申办固话业务，请提供认证照片。'
  req.user.state '认证'
  
wx.state('认证').image (req, res) ->
  req.text '已收到您提交的认证图片，请发送装机地址。'
  req.user.state '装机'
  
wx.state('装机').location (req, res) ->
  res.text "工程师正前往#{req.label}为您安装固话。"
  req.user.state null
```
