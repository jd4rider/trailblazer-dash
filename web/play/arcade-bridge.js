/*
 * Trailblazer Dash — Little Joy Arcade bridge.
 *
 * Load this BEFORE arcade-client.js. It gives the Godot build a tiny, stable
 * surface (`window.TrailblazerArcade`) and teaches the arcade client where the
 * game's save lives, because Godot stores it in IndexedDB rather than
 * localStorage.
 *
 * Every call is defensive: outside the arcade, or if the client failed to load,
 * the game keeps saving locally and nothing throws.
 */
(function () {
  'use strict'

  var GAME_ID = 'trailblazer-dash'
  var SAVE_KEY = GAME_ID + '-save-v1'
  var RESTORE_KEY = 'lja:godot-restore:' + GAME_ID
  var REVISION_KEY = 'trailblazer-dash-achievements'
  var clobbered = false

  var lastPushed = null
  var restored = null
  var pendingAchievements = []

  function decodeBase64(value) {
    try {
      return decodeURIComponent(escape(window.atob(String(value))))
    } catch (error) {
      return ''
    }
  }

  function arcade() {
    return window.LittleJoyArcade || null
  }

  // The client applies a cloud save and then reloads the page so the game boots
  // with it. Memory does not survive that reload, so the snapshot also waits in
  // storage until the game pulls it.
  function stashRestore(value) {
    try {
      window.localStorage.setItem(RESTORE_KEY, value)
    } catch (error) {
      /* private mode: the in-memory copy still covers this page load */
    }
  }

  function takeRestore() {
    try {
      var value = window.localStorage.getItem(RESTORE_KEY)
      if (value) window.localStorage.removeItem(RESTORE_KEY)
      return value
    } catch (error) {
      return null
    }
  }

  function readRevision() {
    try {
      return window.localStorage.getItem(REVISION_KEY) || '0'
    } catch (error) {
      return '0'
    }
  }

  function writeRevision(value) {
    try {
      window.localStorage.setItem(REVISION_KEY, String(value))
    } catch (error) {
      /* private mode */
    }
  }

  function progress() {
    try {
      var raw = window.localStorage.getItem('trailblazer-dash-progress')
      return raw ? JSON.parse(raw) : {}
    } catch (error) {
      return {}
    }
  }

  // The arcade client snapshots this object. Keys are stable strings so older
  // saves survive a game update.
  window.LJA_SNAPSHOT = function () {
    var snapshot = {}
    if (window.__trailblazerSave) snapshot[SAVE_KEY] = window.__trailblazerSave
    var revision = readRevision()
    if (revision !== '0') snapshot[REVISION_KEY] = revision
    return Object.keys(snapshot).length ? snapshot : null
  }

  window.LJA_APPLY_SNAPSHOT = function (keys) {
    if (!keys || typeof keys !== 'object') return
    if (typeof keys[SAVE_KEY] === 'string' && keys[SAVE_KEY].length > 2) {
      restored = keys[SAVE_KEY]
      window.__trailblazerPendingCloud = restored
      stashRestore(restored)
    }
  }

  function displayName(user) {
    if (!user) return 'Guest'
    if (user.email) return String(user.email).split('@')[0]
    var meta = user.user_metadata || {}
    return meta.display_name || meta.name || 'Trailblazer'
  }

  window.TrailblazerArcade = {
    version: 1,

    pushSave: function (base64) {
      var payload = decodeBase64(base64)
      if (!payload) return
      window.__trailblazerSave = payload
      lastPushed = payload
      var client = arcade()
      if (client && typeof client.push === 'function') {
        // Debounced: the game saves after every trail, the network can wait.
        window.clearTimeout(window.__trailblazerPushTimer)
        window.__trailblazerPushTimer = window.setTimeout(function () {
          client.push().catch(function () {})
        }, 2500)
      }
    },

    pullSave: function () {
      var stashed = takeRestore()
      var value = restored || window.__trailblazerPendingCloud || stashed
      restored = null
      window.__trailblazerPendingCloud = null
      return value
    },

    identity: function () {
      var client = arcade()
      var user = client && typeof client.user === 'function' ? client.user() : null
      var state = client && typeof client.status === 'function' ? client.status() : null
      var signedIn = !!(state && state.signedIn)
      return {
        signedIn: signedIn,
        name: displayName(user),
        status: !client ? 'local' : signedIn ? 'synced' : 'local',
        gameId: GAME_ID
      }
    },

    status: function () {
      var client = arcade()
      if (!client) return 'local'
      var state = client && typeof client.status === 'function' ? client.status() : null
      if (!state || !state.signedIn) return 'local'
      return /cloud|saved/i.test(String(state.text || '')) ? 'synced' : 'syncing'
    },

    unlockAchievement: function (id) {
      // Achievements travel inside the save envelope, so remembering the id in
      // the local snapshot is enough for another device to pick them up.
      var slug = String(id)
      if (pendingAchievements.indexOf(slug) === -1) pendingAchievements.push(slug)
      writeRevision(Date.now())
    },

    track: function (base64) {
      var payload = decodeBase64(base64)
      if (!payload) return
      try {
        var event = JSON.parse(payload)
        if (window.console && window.console.debug) {
          window.console.debug('[trailblazer]', event.name, event.props || {})
        }
      } catch (error) {
        /* analytics must never break a run */
      }
    },

    signIn: function () {
      if (location.hash !== '#login') {
        location.hash = '#login'
        location.reload()
      }
    },

    openArcade: function () {
      window.open('https://littlejoyarcade.site/#/games', '_blank', 'noopener')
    }
  }

  if (clobbered) delete window.__trailblazerSave
  window.__trailblazerSave = window.__trailblazerSave || null
  void progress
})()
