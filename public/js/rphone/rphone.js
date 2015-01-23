/* 
 pyphone.js
 * Copyright Aleksandr Borisenko
 * ??? License
 */

var rPhone = rPhone || (function () {

    var rPhoneObject = {};

    var rphone_url = 'http://localhost:8080/rphone';
    var rphone_ws_url = 'ws://localhost:8080/rphone/ws';
    var ws = null;
    var rPhoneInfo = {
        js_version: '0.1',
        srv_version: '0.1',
    };
    var regInfo = {
        registered: 0,
        reg_state: 0,
    };
    var callInfo = {
        state: 'IDLE',      // IDLE, INCOMING, OUTGOING, CONNECTED
        display: '',
    };

    rPhoneObject.onRegStateChanged = function() {};

    rPhoneObject.onCallStateChanged = function() {};

    var rqRegState = function() {
        ws.send(JSON.stringify({
            cmd: 'get_reg_state',
        }));
    };
    var rqCallState = function() {
        ws.send(JSON.stringify({
            cmd: 'get_call_state',
        }));
    };

    var rqVersion = function() {
        ws.send(JSON.stringify({
            cmd: 'get_version',
        }));
    }

    rPhoneObject.init = function() {
        ws = new WebSocket(rphone_ws_url);

        ws.onmessage = function(evt) {
            var jmsg = JSON.parse(evt.data)
            console.log(jmsg);
            if ('reg_state' in jmsg) {
                if (regInfo.reg_state != jmsg['reg_state']) {
                    regInfo.reg_state = jmsg['reg_state'];
                    regInfo.registered = jmsg['registered'];
                    rPhoneObject.onRegStateChanged(regInfo);
                }

            } else if ('call_state' in jmsg) {
                if (callInfo.state != jmsg['call_state']) {
                    callInfo.state = jmsg['call_state'];
                    callInfo.display = jmsg['display'];
                    rPhoneObject.onCallStateChanged(callInfo);
                }
            } else if ('version' in jmsg) {
                
            }
        };

        ws.onclose = function(evt) { 
            console.log("ws close");
        };

        ws.onopen = function(evt) {
            console.log("ws open");
            //rqRegState();
            rqCallState();
            rPhoneObject.initDone();
        };
    };

    rPhoneObject.initDone = function() {};

    rPhoneObject.regState = function() {
        return regInfo.registered;
    };

    rPhoneObject.callState = function() {
        return callInfo.state;
    };

    rPhoneObject.register = function(acc_config) {
        ws.send(JSON.stringify({
            cmd: 'register',
            host: acc_config.host,
            user: acc_config.user,
            password: acc_config.password,
            proxy: acc_config.proxy,
        }));
    };

    rPhoneObject.call = function(to) {
        ws.send(JSON.stringify({
            cmd: 'call',
            to_number: to.number,
        }));
    };
    rPhoneObject.answer = function() {
        ws.send(JSON.stringify({
            cmd: 'answer',
        }));
    };
    rPhoneObject.hangup = function() {
        ws.send(JSON.stringify({
            cmd: 'hangup',
        }));
    };
    rPhoneObject.checkService = function() {
        var result = false;
        $.ajax({
            type: "GET",
            url: rphone_url + "/version",
            data: {},
            timeout: 1000,
            async: false,
            success: function (data, textStatus, jqXHR) {
                if (rPhoneInfo.srv_version == data.version) {
                    result = true;
                }
            },
            error: function (jqXHR, textStatus, errorThrown) {},
        });

        return result;
    };

    return rPhoneObject;
}) ();