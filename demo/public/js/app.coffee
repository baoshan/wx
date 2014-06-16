$ ->

  # ### 
  $(document.body).scrollspy
    target: '#div_affix'
    offset: 200

  # ### 
  smoothScroll.init
    speed: 500
    easing: 'easeInOutCubic'
    offset: 0
    updateURL: off
  
  # tooltip
  $('.hover_tip').hover ->
    $(@).tooltip('toggle')

  # toggle 一段代码
  $("[href='#code_redis_options']").click (event) ->
    event.preventDefault()
    $('#code_redis_options').slideDown()

  # ### 滑至某页
  scrolled = off
  $(window).scroll ->
    return if scrolled
    scrolled = on
    setTimeout ->
      scrolled = off
      scroll_top = $(window).scrollTop()
      $('.page').each ->
        if scroll_top > $(@).prev().position().top + 120
          $(@).addClass('scrolled_to')
          if $(@).is('#div_subscribe_list')
            render_subscribers() unless render_subscribers.rendered
            render_subscribers.rendered = on
    , 400

  $('#qrcode_home').scan ->
    console.log 'home'
    setTimeout ->
      $('body, html').animate(scrollTop: $('#div_home').height())
    , 2400

  # ### QRCODE_CLIENT_LOGIN
  $('#登录二维码').scan (user) ->
    {headimgurl: src, nickname: title} = user
    $img = $ "<img src='#{src}' /><p>#{title}</p>"
    $(@).replaceWith($img)
    setTimeout (=> $img.parent().addClass('loggedin')), 4000

  # ### QRCODE_CLIENT_TEMPORARY
  $('.临时二维码').scan ->
    # console.log 'temp'
    # $(@).parent().addClass('scanned')

  # ### QRCODE_CLIENT_PERMANENT
  $('#永久二维码').scan ({nickname: title, headimgurl: src}) ->
    $img = $("<img src='#{src}' title='#{title}' />")
    $('#div_headimgs').append($img)
    $img.load -> $(@).addClass('loaded')

  # ### MARKDOWN2BUTTONS
  template_buttons = $('#template_div_buttons').html()
  do sync_buttons = ->
    console.log Mustache.render template_buttons, markdown_2_json $('#textarea_markdown').val()
    json = markdown_2_json $('#textarea_markdown').val()
    $('#div_buttons').html(Mustache.render template_buttons, json)
    $('#div_edit_button_demo_code code').html(JSON.stringify json, null, '  ')

  $('#textarea_markdown').on 'input', sync_buttons

  render_subscribers = ->
    randoms = [0...100].sort -> if Math.random() > 0.5 then 1 else -1
    $("#div_subscribe_list.page .bottom .row").append Array(101).join("<div class='col-md-1' />")
    for headimgurl, i in headimgurls
      do (headimgurl, i) ->
        setTimeout ->
          selector = "#div_subscribe_list.page .bottom .row > div:nth-child(#{randoms[i]})"
          $(selector).css('background-image', "url(#{headimgurl})")
          setTimeout ->
            $(selector).addClass('loaded')
          , 500
        , i * 500
