/* 
 pyphone.js
 * Copyright Aleksandr Borisenko
 * ??? License
 */

var pyPhone = pyPhone || (function () {

    var pyPhoneObject = {};

    var pyphone_url = 'http://localhost:8080/pyphone';
    var pyphone_ws_url = 'ws://localhost:8080/pyphone/ws';
    var ws = null;
    var pyPhoneInfo = {
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

    pyPhoneObject.onRegStateChanged = function() {};

    pyPhoneObject.onCallStateChanged = function() {};

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

    pyPhoneObject.init = function() {
        ws = new WebSocket(pyphone_ws_url);

        ws.onmessage = function(evt) {
            var jmsg = JSON.parse(evt.data)
            console.log(jmsg);
            if ('reg_state' in jmsg) {
                if (regInfo.reg_state != jmsg['reg_state']) {
                    regInfo.reg_state = jmsg['reg_state'];
                    regInfo.registered = jmsg['registered'];
                    pyPhoneObject.onRegStateChanged(regInfo);
                }

            } else if ('call_state' in jmsg) {
                if (callInfo.state != jmsg['call_state']) {
                    callInfo.state = jmsg['call_state'];
                    callInfo.display = jmsg['display'];
                    pyPhoneObject.onCallStateChanged(callInfo);
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
            pyPhoneObject.initDone();
        };
    };

    pyPhoneObject.initDone = function() {};

    pyPhoneObject.regState = function() {
        return regInfo.registered;
    };

    pyPhoneObject.callState = function() {
        return callInfo.state;
    };

    pyPhoneObject.register = function(acc_config) {
        ws.send(JSON.stringify({
            cmd: 'register',
            host: acc_config.host,
            user: acc_config.user,
            password: acc_config.password,
            proxy: acc_config.proxy,
        }));
    };

    pyPhoneObject.call = function(to) {
        ws.send(JSON.stringify({
            cmd: 'call',
            to_number: to.number,
        }));
    };
    pyPhoneObject.answer = function() {
        ws.send(JSON.stringify({
            cmd: 'answer',
        }));
    };
    pyPhoneObject.hangup = function() {
        ws.send(JSON.stringify({
            cmd: 'hangup',
        }));
    };
    pyPhoneObject.checkService = function() {
        var result = false;
        $.ajax({
            type: "GET",
            url: pyphone_url + "/version",
            data: {},
            timeout: 1000,
            async: false,
            success: function (data, textStatus, jqXHR) {
                if (pyPhoneInfo.srv_version == data.version) {
                    result = true;
                }
            },
            error: function (jqXHR, textStatus, errorThrown) {},
        });

        return result;
    };

    return pyPhoneObject;
}) ();