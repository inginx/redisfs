fs        = require 'fs'
vows      = require 'vows'
assert    = require 'assert'
{setup}    = require './helper'
{redisfs} = require '../src/index.coffee'

fixture  = redisfs()

# start clean
redis = fixture.redis
redis.flushdb()

vows.describe('redis2file').addBatch(
  ###################################################
  'redis2file with defaults':
    topic: -> setup (err, file) => fixture.file2redis file, @callback
    'generates a file': (err, result) ->
      assert.equal 'OK', result.reply
    'writes to a temp file':
      topic: (result) -> fixture.redis2file result.key, @callback
      'contents of resulting file':
        topic: (result) -> fs.readFile result, 'utf8', @callback
        'should be test': (data) ->
          assert.equal 'test', data
    teardown: (result) -> redis.flushdb()

).export module

