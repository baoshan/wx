fs = require 'fs'

console.log md = "#{fs.readFileSync('menu.md')}"

buttons = []

parse = (line) ->
  if match = line.match /\[(.*)\]\((.*)\)/
    type : 'view'
    name : match[1]
    url  : match[2]
  else
    type : 'click'
    name : line
    key  : line

for line in md.split /\n/
  line = line.trim()
  if match = line.match /^\+(.*)/
    buttons.push parse match[1].trim()
  else if match = line.match /^\-(.*)/
    (buttons[buttons.length - 1].sub_button ?= []).push parse match[1].trim()

console.log JSON.stringify buttons, null, "  "
