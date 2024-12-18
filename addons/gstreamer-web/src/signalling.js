/**
* @typedef {Object} WebRTCDemoSignalling
* @property {function} ondebug - Callback fired when a new debug message is set.
* @property {function} onstatus - Callback fired when a new status message is set.
* @property {function} onerror - Callback fired when an error occurs.
* @property {function} onice - Callback fired when a new ICE candidate is received.
* @property {function} onsdp - Callback fired when SDP is received.
* @property {function} connect - initiate connection to server.
* @property {function} disconnect - close connection to server.
*/

class WebRTCDemoSignalling {
    /**
     * Interface to WebRTC demo signalling server.
     * Protocol: https://github.com/GStreamer/gstreamer/blob/main/subprojects/gst-examples/webrtc/signalling/Protocol.md
     *
     * @constructor
     * @param {URL} [server]
     *    The URL object of the signalling server to connect to, created with `new URL()`.
     *    Signalling implementation is here:
     *      https://github.com/GStreamer/gstreamer/tree/main/subprojects/gst-examples/webrtc/signalling
     */
    constructor(server) {
        /**
         * @private
         * @type {URL}
         */
        this._server = server;

        /**
         * @private
         * @type {number}
         */
        this.peer_id = 1;

        /**
         * @private
         * @type {WebSocket}
         */
        this._ws_conn = null;

        /**
         * @event
         * @type {function}
         */
        this.onstatus = null;

        /**
         * @event
         * @type {function}
         */
        this.onerror = null;

        /**
         * @type {function}
         */
        this.ondebug = null;

        /**
         * @event
         * @type {function}
         */
        this.onice = null;

        /**
         * @event
         * @type {function}
         */
        this.onsdp = null;

        /**
         * @event
         * @type {function}
         */
        this.ondisconnect = null;

        /**
         * @type {string}
         */
        this.state = 'disconnected';

        /**
         * @type {number}
         */
        this.retry_count = 0;
    }

    /**
     * Sets status message.
     *
     * @private
     * @param {String} message
     */
    _setStatus(message) {
        if (this.onstatus !== null) {
            this.onstatus(message);
        }
    }

    /**
     * Sets a debug message.
     * @private
     * @param {String} message
     */
    _setDebug(message) {
        if (this.ondebug !== null) {
            this.ondebug(message);
        }
    }

    /**
     * Sets error message.
     *
     * @private
     * @param {String} message
     */
    _setError(message) {
        if (this.onerror !== null) {
            this.onerror(message);
        }
    }

    /**
     * Sets SDP
     *
     * @private
     * @param {String} message
     */
    _setSDP(sdp) {
        if (this.onsdp !== null) {
            this.onsdp(sdp);
        }
    }

    /**
     * Sets ICE
     *
     * @private
     * @param {RTCIceCandidate} icecandidate
     */
    _setICE(icecandidate) {
        if (this.onice !== null) {
            this.onice(icecandidate);
        }
    }

    /**
     * Fired whenever the signalling websocket is opened.
     * Sends the peer id to the signalling server.
     *
     * @private
     * @event
     */
    _onServerOpen() {
        // Send local device resolution and scaling with HELLO message.
        var currRes = webrtc.input.getWindowResolution();
        var meta = {
            "res": parseInt(currRes[0]) + "x" + parseInt(currRes[1]),
            "scale": window.devicePixelRatio
        };
        this.state = 'connected';
        this._ws_conn.send(`HELLO ${this.peer_id} ${btoa(JSON.stringify(meta))}`);
        this._setStatus("服务器注册中, peer ID: " + this.peer_id);
        this.retry_count = 0;
    }

    /**
     * Fired whenever the signalling websocket emits and error.
     * Reconnects after 3 seconds.
     *
     * @private
     * @event
     */
    _onServerError() {
        this._setStatus("连接错误, 3秒后重试.");
        this.retry_count++;
        if (this._ws_conn.readyState === this._ws_conn.CLOSED) {
            setTimeout(() => {
                if (this.retry_count > 3) {
                    window.location.reload();
                } else {
                    this.connect();
                }
            }, 3000);
        }
    }

    /**
     * Fired whenever a message is received from the signalling server.
     * Message types:
     *   HELLO: response from server indicating peer is registered.
     *   ERROR*: error messages from server.
     *   {"sdp": ...}: JSON SDP message
     *   {"ice": ...}: JSON ICE message
     *
     * @private
     * @event
     * @param {Event} event The event: https://developer.mozilla.org/en-US/docs/Web/API/MessageEvent
     */
    _onServerMessage(event) {
        this._setDebug("server message: " + event.data);

        if (event.data === "HELLO") {
            this._setStatus("服务器已注册.");
            this._setStatus("等待推流.");
            return;
        }

        if (event.data.startsWith("ERROR")) {
            this._setStatus("服务器错误: " + event.data);
            // TODO: reset the connection.
            return;
        }

        // Attempt to parse JSON SDP or ICE message
        var msg;
        try {
            msg = JSON.parse(event.data);
        } catch (e) {
            if (e instanceof SyntaxError) {
                this._setError("error parsing message as JSON: " + event.data);
            } else {
                this._setError("failed to parse message: " + event.data);
            }
            return;
        }

        if (msg.sdp != null) {
            this._setSDP(new RTCSessionDescription(msg.sdp));
        } else if (msg.ice != null) {
            var icecandidate = new RTCIceCandidate(msg.ice);
            this._setICE(icecandidate);
        } else {
            this._setError("unhandled JSON message: " + msg);
        }
        playStream()
    }

    /**
     * Fired whenever the signalling websocket is closed.
     * Reconnects after 1 second.
     *
     * @private
     * @event
     */
    _onServerClose() {
        if (this.state !== 'connecting') {
            this.state = 'disconnected';
            this._setError("Server closed connection.");
            if (this.ondisconnect !== null) this.ondisconnect();
        }
    }

    /**
     * Initiates the connection to the signalling server.
     * After this is called, a series of handshakes occurs between the signalling
     * server and the server (peer) to negotiate ICE candidates and media capabilities.
     */
    connect() {
        this.state = 'connecting';
        this._setStatus("正在连接服务器.");

        this._ws_conn = new WebSocket(this._server);

        // Bind event handlers.
        this._ws_conn.addEventListener('open', this._onServerOpen.bind(this));
        this._ws_conn.addEventListener('error', this._onServerError.bind(this));
        this._ws_conn.addEventListener('message', this._onServerMessage.bind(this));
        this._ws_conn.addEventListener('close', this._onServerClose.bind(this));
    }

    /**
     * Closes connection to signalling server.
     * Triggers onServerClose event.
     */
    disconnect() {
        this._ws_conn.close();
    }

    /**
     * Send ICE candidate.
     *
     * @param {RTCIceCandidate} ice
     */
    sendICE(ice) {
        this._setDebug("sending ice candidate: " + JSON.stringify(ice));
        this._ws_conn.send(JSON.stringify({ 'ice': ice }));
    }

    /**
     * Send local session description.
     *
     * @param {RTCSessionDescription} sdp
     */
    sendSDP(sdp) {
        this._setDebug("sending local sdp: " + JSON.stringify(sdp));
        this._ws_conn.send(JSON.stringify({ 'sdp': sdp }));
    }
}