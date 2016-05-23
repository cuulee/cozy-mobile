mockery = require 'mockery'
should = require('chai').should()
PouchDB = require 'pouchdb'


cozyFile =
    _id: 'folderName'
    name: 'fileName'
    binary:
        file:
            id: 'binary_id'
            rev: 'binary_rev'
db = new PouchDB 'db', db: require 'memdown'
requestCozy = {}


module.exports = describe 'FileCacheHandler Test', ->


    before =>
        mockery.enable
            warnOnReplace: false
            warnOnUnregistered: false
            useCleanCache: true

        filesystem =
            initialize: (callback) ->
                callback null, "donwloads", "cache"

        mockery.registerMock '../replicator/filesystem', filesystem
        FileCacheHandler = require '../../../app/lib/file_cache_handler'
        @fileCacheHandler = new FileCacheHandler db, requestCozy


    after ->
        mockery.deregisterAll()
        mockery.disable()


    describe 'getFileName Test', ->


        it 'must have return a file name', ->
            folderName = @fileCacheHandler.getFileName cozyFile
            folderName.should.be.equal cozyFile.name
            folderName.should.to.be.a 'string'


        it 'must throw an error if cozyFile have not name field', ->
            @fileCacheHandler.getFileName.should.throw()


    describe 'getFolderName Test', ->


        it 'must have return a folder name', ->
            folderName = @fileCacheHandler.getFolderName cozyFile
            folderName.should.be.equal cozyFile._id
            folderName.should.to.be.a 'string'


        it 'must have return an error if cozyFile have not _id field', ->
            @fileCacheHandler.getFolderName.should.throw()


    describe 'isCached Test', ->


        it 'must have return if is not cached', ->
            isCached = @fileCacheHandler.isCached cozyFile
            isCached.should.be.false


        it 'must have return if is cached', ->
            @fileCacheHandler.cache[cozyFile._id] = true
            isCached = @fileCacheHandler.isCached cozyFile
            isCached.should.be.true


    describe 'isSameBinary Test', ->


        it 'must have return if is not the same binary when is not on cache', ->
            isCached = @fileCacheHandler.isSameBinary cozyFile
            isCached.should.be.false


        it 'must have return if is not the same binary when is not same rev', ->
            @fileCacheHandler.cache[cozyFile._id] = version: 'not same'
            isCached = @fileCacheHandler.isSameBinary cozyFile
            isCached.should.be.false


        it 'must have return if is the same binary', ->
            @fileCacheHandler.cache[cozyFile._id] =
                version: cozyFile.binary.file.rev
            isCached = @fileCacheHandler.isSameBinary cozyFile
            isCached.should.be.true


    describe 'isSameName Test', ->


        it 'must have return if is not the same name when is not on cache', ->
            isCached = @fileCacheHandler.isSameName cozyFile
            isCached.should.be.false


        it 'must have return if is not the same name', ->
            @fileCacheHandler.cache[cozyFile._id] = name: 'not same'
            isCached = @fileCacheHandler.isSameName cozyFile
            isCached.should.be.false


        it 'must have return if is the same name', ->
            @fileCacheHandler.cache[cozyFile._id] =
                name: cozyFile.name
            isCached = @fileCacheHandler.isSameName cozyFile
            isCached.should.be.true


    describe 'saveInCache Test', ->


        it 'must save file in cache', (done) ->
            delete @fileCacheHandler.cache[cozyFile._id]
            # before test if not exist
            should.not.exist @fileCacheHandler.cache[cozyFile._id]
            db.get cozyFile._id, (err, doc) =>
                should.exist err
                err.status.should.be.equal 404
                should.not.exist doc
                # save
                @fileCacheHandler.saveInCache cozyFile, (err) =>
                    # after test if exist
                    should.not.exist err
                    should.exist @fileCacheHandler.cache[cozyFile._id]
                    db.get cozyFile._id, (err, doc) ->
                        should.not.exist err
                        should.exist doc
                        done()


    describe 'removeInCache Test', ->


        it 'must remove file in cache', (done) ->
            db.put cozyFile
            db.get cozyFile._id, (err, doc) =>
                should.not.exist err
                should.exist doc
                @fileCacheHandler.cache[cozyFile._id] = true
                @fileCacheHandler.removeInCache cozyFile, (err) =>
                    should.not.exist err
                    @fileCacheHandler.isCached(cozyFile).should.be.false
                    db.get cozyFile._id, (err, doc) ->
                        should.exist err
                        should.not.exist doc
                        done()


        it 'must not return an error when doc not exist', (done) ->
            @fileCacheHandler.removeInCache cozyFile, (err) ->
                should.not.exist err
                done()
