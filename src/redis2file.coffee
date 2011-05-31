coffee         = require 'coffee-script'
redisfs        = require './index'
{OptionParser} = require 'coffee-script/lib/optparse'

log = console.log

require.extensions['.coffee'] = (module, filename) ->
   content = coffee.compile fs.readFileSync filename, 'utf8'
   module._compile content, filename

usage = '''
  Usage:
    redis2file [OPTIONS] key
'''

switches = [
  ['-h', '--help', 'Displays options']
  ['-v', '--version', "Shows file2redis' version."]
  ['-f', '--file [STRING]', 'The path of the file to write to. (Defaults: generated temp file)']
  ['-e', '--encoding [STRING]', 'The encoding to use. (Defaults: utf8)']
  ['-p', '--prefix [STRING]', 'The filename prefix to use. (Defaults: redisfs)']
  ['-s', '--suffix [STRING]', 'The filename suffix to use.']
  ['-d', '--deleteKey', 'Indicator to delete the key after the op. (Defaults: false)']
]

argv = process.argv[2..]
@run = ->
  parser = new OptionParser switches, usage
  options = parser.parse argv
  args = options.arguments
  delete options.arguments

  if args.length is 0 and argv.length is 0
    log parser.help()
    log "v#{redisfs.version}"

  log parser.help() if options.help
  log "v#{redisfs.version}" if options.version

  if args[0]
    redisfs = redisfs.redisfs
      file      : options.file if options.file?
      encoding  : options.encoding if options.encoding?
      deleteKey : options.deleteKey or off

    redisfs.redis2file args[0], (err, result) ->
      if err? then log "error: #{err}" else log "OK  file -> #{result}"
      redisfs.end false
