express = require 'express'
fs = require 'fs'
path = require 'path'
router = express.Router()
source = (fs.readFileSync(path.join(__dirname, '../app.coffee')).toString() + fs.readFileSync(path.join(__dirname, '../public/js/app.coffee')).toString())
.split(/# ###/)
.reduce (memo, block) ->
  match = block.match(/(.*)\n((?:.*\n)*)/)
  return memo unless match
  lines = match[2].split(/\n/).filter((line) -> not line.match /# ## |# # /)
  spaces = lines[0].match(/^\s+/)?[0]?.length or 0
  console.log match[1].trim(), spaces, lines[0]
  lines = lines.map (line) -> line.substr(spaces)
  memo[match[1].trim()] = lines.join('\n').trim()
  if match[1].trim() is 'QRCODE_CLIENT_LOGIN'
    memo[match[1].trim()] = memo[match[1].trim()].split(/\n/)[0...-1].join('\n')
  memo
, {}
source.markdown_2_json = 'var markdown_2_json = ' + global.wx.markdown_2_json.toString()

console.log Object.keys(source)

router.get '/', (req, res) ->
  console.log source.subscribers = module.parent.exports.subscribers()
  source.headimgurls = JSON.stringify source.subscribers.map ({headimgurl}) -> headimgurl.replace(/\/0$/, '/132')
  res.render 'index', source

module.exports = router
