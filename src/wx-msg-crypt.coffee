crypto = require 'crypto'
xml2js = require 'xml2js'

# wrap the PKCS7 encoder/decoder.
PKCS7 = do ->

  block_size = 32

  # encode with PKCS7
  encode: (data) ->
    amount_to_pad = block_size - (data.length % block_size)
    if amount_to_pad == 0
      amount_to_pad = block_size
    buf = new Buffer(amount_to_pad)
    buf.fill String.fromCharCode(amount_to_pad)
    Buffer.concat [data, buf]

  # decode with PKCS7
  decode: (data) ->
    pad = data.readUInt8 data.length - 1
    if pad < 1 || pad > 32
      pad = 0
    console.log pad
    data.slice 0, data.length - pad

class Prpcrypt

  constructor: (key) ->
    @key = new Buffer(key + '=', 'base64')

  get_random_str = ->
    str = ''
    str_pol = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefghijklmnopqrstuvwxyz"
    for i in [0..15]
      str += str_pol[parseInt(Math.random() * str_pol.length)]
    str

  encrypt: (text, appid) ->
    # assemble the encrypted message.
    msg_len = 16 + 4 + Buffer.byteLength(text) + appid.length
    buf = new Buffer(msg_len)
    buf.write get_random_str(), 0
    buf.writeUInt32BE Buffer.byteLength(text), 16
    buf.write text, 20
    buf.write appid, Buffer.byteLength(text) + 20
    # Encrypt with PKCS7 and AES256 CBC.
    iv = @key.slice(0, 16)
    #pkc_encoder = new PKCS7Encoder()
    buf = PKCS7.encode buf
    cipher = crypto.createCipheriv 'aes-256-cbc', @key, iv
    cipher.setAutoPadding false
    cipherChunks = [
      cipher.update buf, 'binary', 'base64'
      cipher.final 'base64'
    ]
    cipherChunks.join ''

  decrypt: (text, appid) ->
    # Decrypt with AES256 CBC
    iv = @key.slice(0, 16)
    decipher = crypto.createDecipheriv 'aes-256-cbc', @key, iv
    decipher.setAutoPadding false
    plainChunks = [
      decipher.update text, 'base64'
      decipher.final()
    ]
    buf = Buffer.concat plainChunks
    # extract the message part.
    buf = PKCS7.decode buf
    buf = buf.slice 20, buf.length - appid.length
    buf.toString 'utf8'

generated_signature = (token, timestamp, nonce, encrypt) ->
  console.log "#{token}-#{timestamp}-#{nonce}-#{encrypt}"
  sha1 = crypto.createHash 'sha1'
  sha1.update [token, timestamp, nonce, encrypt].sort().join ''
  sha1.digest 'hex'

class WXBizMsgCrypt

  constructor: (@token, @key, @appId) ->
    if @key.length != 43
      throw 'Key is not valid.'

  encrypt: (msg, timestamp, nonce) ->
    pc = new Prpcrypt @key
    encrypt = pc.encrypt msg, @appId
    signature = generated_signature @token, timestamp, nonce, encrypt
    "<xml>
      <Encrypt><![CDATA[#{encrypt}]]></Encrypt>
      <MsgSignature><![CDATA[#{signature}]]></MsgSignature>
      <TimeStamp>#{timestamp}</TimeStamp>
      <Nonce><![CDATA[#{nonce}]]></Nonce>
    </xml>"

  decrypt: (msg, callback) ->
    xml2js.parseString msg, (err, result) =>
      throw err if err
      xml = result.xml
      console.log xml
      if xml.Encrypt
        pc = new Prpcrypt @key
        xml2js.parseString pc.decrypt(xml.Encrypt[0], @appId), callback
      else
        callback 'Not encrypted.', null

# Expose the class.
module.exports = WXBizMsgCrypt
