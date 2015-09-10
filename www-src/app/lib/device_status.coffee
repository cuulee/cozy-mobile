log = require('/lib/persistent_log')
    prefix: "device status"
    date: true

# Store callbacks, while waiting (with timeout) for battery event.
callbacks = []
battery = null
timeout = true

# Dispatch on each callback.
callbackWaiting = (err, ready, msg) ->
    callback err, ready, msg  for callback in callbacks
    callbacks = []


# Register to battery events. To call after 'deviceRedy' event.
module.exports.initialize = ->
    timeout = true

    log.info "initialize device status."
    window.addEventListener 'batterystatus', (newStatus) =>
        # timeout watchdog isn't usefull anymore, so we turn the flag
        timeout = false
        battery = newStatus
        checkReadyForSync()

# Check if device is ready for heavy works:
# - battery as more than 20%
# - on wifi if syncOnWifi[only] options is activated.
# Callback should have (err, (boolean)ready, message) signature.
module.exports.checkReadyForSync = checkReadyForSync = (callback)->
    callbacks.push callback if callback?

    # if we don't have informations about battery status, wait for it
    # with a 4' timeout.
    unless battery? #
        setTimeout () =>
            if timeout
                # We reached timeout, and a batterystatus event hasn't fired yet
                timeout = false
                callbackWaiting new Error "No battery informations"
        , 4 * 1000

        return

    unless (battery.level > 20 or battery.isPlugged)
        log.info "NOT ready on battery low."
        return callbackWaiting null, false, 'no battery'
    if app.replicator.config.get('syncOnWifi') and
       (not (navigator.connection.type is Connection.WIFI))
        log.info "NOT ready on no wifi."
        return callbackWaiting null, false, 'no wifi'

    log.info "ready to sync."
    callbackWaiting null, true
