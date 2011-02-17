exports.version = '0.1.0'

#
# Sets up a new RedisFs instance.
#
# options - Optional Hash of options.
#   redis     - Existing instance of node_client.
#   host      - String Redis host.  (Default: Redis' default)
#   port      - Integer Redis port.  (Default: Redis' default)
#   namespace - String namespace prefix for generated Redis keys.
#               (Default: redisfs).
#   database  - Optional Integer of the Redis database to select.
#   dir       - Optional path to write files out to for generated files.
#   prefix    - Optional prefix to use for generated files.
#   suffix    - Optional suffix to use for generated files. 
#
exports.redisfs = (options) ->
  new exports.RedisFs options

#
# Dependencies
#
_     = require 'underscore'
fs    = require 'fs'
temp  = require 'temp'
uuid  = require 'node-uuid'
redis = require 'redis'
log   = console.log

#
# Util to pump files in & out of redis.
#
class RedisFs
  constructor: (options = {}, @keys = []) ->
    @redis      = options.redis or connectToRedis options
    @namespace  = options.namespace or 'redisfs'
    @redis.select options.database if options.database?

  #
  # Pumps a file's contents into a redis key. 
  #   filename   - The full path to the file to consume
  #   options    -  
  #     key      - Optional redis key.  If omitted a key will be 
  #                generated using a uuid.
  #     encoding - Optional file encoding, defaults to utf8.
  #   callback   - Recieves either an error as the first param
  #                or success hash that contains the key and reply
  #                as the second param.
  #
  file2redis: (filename, options, callback) ->
    if _.isFunction options
      callback = options
      options = {}
    key = options.key or "#{@namespace}:#{uuid()}"
    encoding = options.encoding or 'utf8'
    @keys.push key unless options.key
    fs.readFile filename, encoding, (err, data) =>
      if err? then callback err else @set key, data, callback

  #
  # Pumps a redis value to a file. 
  #   key        - The redis key to fetch.
  #   options
  #     filename - Optional filename to write to. assumes the file is
  #                preexisting and writable.  If ommitted a temp file 
  #                will be generated.
  #     dir      - Optional path to write files out to for generated files.
  #                This overrides the instance level options is specified.
  #     prefix   - Optional prefix to use for generated files.
  #                This overrides the instance level options is specified.
  #     suffix   - Optional suffix to use for generated files. 
  #                This overrides the instance level options is specified.
  #     encoding - Optional file encoding, defaults to utf8
  #   callback   - Receives the and error as the first param
  #                or a success hash that contains the path
  #                and a fd to the file.
  #
  redis2file: (key, options, callback) ->
    if _.isFunction options
      callback = options
      options = {}
    encoding = options.encoding or 'utf8'
    if options.filename?
      @get key, (err, value) =>
        if err? then callback err else @write options.filename, value, encoding, callback
    else
      @open key, encoding, callback

  #
  # end the redis connection and del all the keys generated during
  # the session.  pass true as the first argument to cleanup the
  # generated keys and an optional callback.  callback is not
  # invoked cleanup is not on.
  #
  end: (cleanup, callback) ->
    callback = cleanup if _.isFunction cleanup
    if cleanup is on
      multi = @redis.multi()
      multi.del key for key in @keys
      multi.exec (err, replies) =>
        log "Unable to del all generated keys #{JSON.stringify replies}" if err?
        callback(err, replies) if callback?
        @redis.quit()
    else
      @redis.quit()

  #
  # @private
  # gets the value of the key.  callback will receive the value.
  #
  get: (key, callback) ->
    @redis.get key, (err, value) =>
      if err? callback err else callback null, value

  #
  # @private
  # sets the value to a new redis key.  callback will
  # receive the new key and the redis reply.
  #
  set: (key, value, callback) ->
    @redis.set key, value, (err, reply) =>
      if err? then callback err else callback null, {key: key, reply: reply}

  #
  # @private
  # pumps a redis value into a generated temp file. callback will
  # receive the filename
  #
  open: (key, encoding, callback) ->
    temp.open 'redisfs', (err, file) =>
      if err?
        callback err
      else
        @redis2file key, {filename: file.path, encoding: encoding}, callback

  #
  # @private
  # write to a file
  #
  write: (filename, value, encoding, callback) ->
    fs.writeFile filename, value, encoding, (err) =>
      if err? then callback err else callback null, filename

#
# fetch a redis client
#
connectToRedis = (options) ->
  redis.createClient options.port, options.host

exports.RedisFs = RedisFs
