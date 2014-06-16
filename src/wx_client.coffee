$ = jQuery

# 注册二维码扫描事件
#
# 为`jQuery`对象扩展`scan`方法，注册或触发二维码扫描事件。
$.fn.scan = (handler, options) ->

  # 直接调用`scan`时，触发`jQuery`对象的`scan`事件。
  return @trigger('scan') unless arguments.length

  # 对选区内二维码逐一处理，等候其扫描事件。
  @each ->

    msg_ids = {}

    # + 缓存原始图片地址，供载入失败或失效时刷新用；
    # + 变量`img`实时指向有效的图片元素；
    # + 临时二维码有效时间为`1800`秒。
    return unless src = $(@).attr('src')
    continuous = $(@).attr('continuous')?
    img = @
    expires = 1800 * 1000

    # 手工触发`scan`时，用自定义参数调用二维码扫描句柄。
    $(@).on 'scan', null, null, (event, args...) ->
      handler?.apply(img, args)

    # 增补当前时间生成新地址，以防浏览器缓存原图片。
    new_src = ->
      w_query = src.indexOf('?') isnt -1
      "#{src}#{if w_query then '&' else '?'}t=#{Date.now()}"

    # 二维码图片载入后：
    load = ->

      # 1. 显示图片；
      # 2. 轮询扫码结果。
      $(img).show()
      do polling = =>
        return unless $(img).is(':visible')
        timeout = setTimeout(polling, 25000)
        do ->
          start = Date.now()
          scan_url = encodeURI(decodeURI(src.replace(/(.*)(\/qrcode)($|((\?|\/).*))/i, '$1/scan$3')))
          scan_url = if scan_url.indexOf('?') isnt -1 then scan_url + "&t=#{Date.now()}" else scan_url + "?t=#{Date.now()}"
          $.ajax(scan_url)
          .success (params) ->
            clearTimeout(timeout)
            $(img).addClass('scanned')
            [msg_id, params...] = params
            return if msg_ids[msg_id]
            msg_ids[msg_id] = 1
            handler?.apply(img, params)
            polling() if continuous

          # 请求失败时，
          .fail (xhr, status) ->
            return if xhr.status  is 404
            clearTimeout(timeout)
            polling()

      # 二维码失效后刷新二维码：
      # 
      # 1. 如果图片已经不可见，不更新图片；
      # 2. 创建新的图片元素，设置图片地址；
      # 3. 载入成功后，替换原图，重新计时；
      # 4. 载入失败后，重复刷新二维码流程。
      return if permanent = src.match /\/qrcode\/\d+(\?|$)/
      setTimeout refresh = =>
        return unless $(img).is(':visible')
        $(img)
        .clone()
        .attr('src', new_src())
        .hide()
        .appendTo(document.body)
        .load ->
          return unless $(img).is(':visible')
          img = $(@).replaceAll(img).show().get(0)
          setTimeout(refresh, expires)
        .error ->
          $(@).remove()
          refresh()
      , expires

    # 图片载入失败时，更新图片地址（重试）。
    error = -> $(@).attr('src', new_src())

    # 注册载入成功与失败事件。
    $(@).load(load).error(error)

    # 如已经载入，手动触发载入事件。
    $(@).load() if @complete
