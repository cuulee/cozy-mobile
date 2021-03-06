async = require 'async'
AndroidAccount = require './android_account'
CozyToAndroidContact = require "../transformer/cozy_to_android_contact"
Permission = require '../../lib/permission'

log = require('../../lib/persistent_log')
    prefix: "ContactImporter"
    date: true

continueOnError = require('../../lib/utils').continueOnError log

###*
 * Import changes (dirty rows) from android contact database to PouchDB
 *
###
module.exports = class ContactImporter

    constructor: (@replicateDb) ->
        @replicateDb ?= app.init.database.replicateDb
        @transformer = new CozyToAndroidContact()
        @permission = new Permission()


    synchronize: (callback) ->
        success = =>
            # Go through modified contacts (dirtys)
            # delete, update or create....

            fields = [navigator.contacts.fieldType.dirty]

            successCB = (contacts) =>
                log.info "syncPhone2Pouch #{contacts.length} contacts."
                # contact to update number. contacts.length
                async.eachSeries contacts, (contact, cb) =>
                    setImmediate => # helps refresh UI
                        if contact.deleted
                            @_delete contact, continueOnError cb
                        else if contact.sourceId
                            @_update contact, continueOnError cb
                        else
                            @_create contact, continueOnError cb
                , callback

            filter = "1"
            multiple = true
            desiredFields = []
            accountType = AndroidAccount.TYPE
            accountName = AndroidAccount.NAME
            findOptions = new ContactFindOptions filter, multiple, \
                    desiredFields, accountType, accountName

            navigator.contacts.find fields, successCB, callback, findOptions

        @permission.checkPermission 'contacts', success, callback


    # Update contact in pouchDB with specified contact from phone.
    # @param phoneContact cordova contact format.
    _update: (phoneContact, callback) ->
        async.parallel
            fromPouch: (cb) =>
                @replicateDb.get phoneContact.sourceId,  attachments: true, cb

            fromPhone: (cb) =>
                @transformer.reverseTransform phoneContact, cb
        , (err, res) =>
            return callback err if err

            # _.extend : Keeps not android compliant data of the 'cozy'-contact
            contact = _.extend res.fromPouch, res.fromPhone

            # remove duplicated url
            if contact.url
                for data of contact.datapoints
                    if data.name is 'url' and data.value is contact.url
                        delete contact.url

            # remove duplicated birthday
            if contact.bday
                contact.datapoints = contact.datapoints.filter (data) ->
                    data.name isnt 'about' or data.type isnt 'birthday'

            # remove duplicated datapoint
            dataJson = []
            dataJson.push JSON.stringify data for data in contact.datapoints
            dataJson = _.uniq dataJson
            contact.datapoints = []
            contact.datapoints.push JSON.parse data for data in dataJson

            if contact._attachments?.picture?
                picture = contact._attachments.picture

                if res.fromPouch._attachments?.picture?
                    oldPicture = res.fromPouch._attachments?.picture
                    if oldPicture.data is picture.data
                        picture.revpos = oldPicture.revpos
                    else
                        picture.revpos = 1 + \
                            parseInt contact._rev.split('-')[0]

            @replicateDb.put contact, (err, idNrev) =>
                return callback err if err
                @_undirty phoneContact, idNrev, callback


    # Create a new contact in app's pouchDB from newly created phone contact.
    # @param phoneContact cordova contact format.
    # @param retry retry lighter update after a failed one.
    _create: (phoneContact, callback) ->
        @transformer.reverseTransform phoneContact, (err, fromPhone) =>
            contact = _.extend
                docType: 'contact'
                tags: []
            , fromPhone

            if contact._attachments?.picture?
                contact._attachments.picture.revpos = 1

            @replicateDb.post contact, (err, idNrev) =>
                return callback err if err
                @_undirty phoneContact, idNrev, callback



    # Delete the specified contact in app's pouchdb.
    # @param phoneContact cordova contact format.
    _delete: (phoneContact, callback) ->
        toDelete =
            docType: 'contact'
            _id: phoneContact.sourceId
            _rev: phoneContact.sync2
            _deleted: true

        @replicateDb.put toDelete, (err, res) ->
            return callback err if err
            phoneContact.remove (-> callback()), callback, \
                    callerIsSyncAdapter: true



    # Notify to Android that the contact have been synchronized with the server.
    # @param dirtyContact cordova contact format.
    # @param idNrew object with id and rev of pouchDB contact.
    _undirty: (dirtyContact, idNrev, callback) ->
        # undirty and set id and rev on phone contact.
        dirtyContact.dirty = false
        dirtyContact.sourceId = idNrev.id
        dirtyContact.sync2 = idNrev.rev

        dirtyContact.save () ->
            callback null
        , callback
        ,
            accountType: AndroidAccount.TYPE
            accountName: AndroidAccount.NAME
            callerIsSyncAdapter: true
