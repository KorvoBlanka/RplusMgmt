/*
 * jQuery webSpeech 1.0.1
 * 
 * [webSpeech]
 * 
 * NO COPYRIGHTS OR LICENSES. DO WHAT YOU LIKE.
 * 
 * http://digipiph.com
 * 
 * File generated: Thur Mar 22 12:18 EST 2013
 */
(function($){

  //START $.fn.webSpeech
  $.fn.webSpeech = function (instanceSettings) {

    //settings
    var defaultSettings = {
      button      : 'webSpeech_button', //id of the initiating button
      lang        : 'en-US',
      format      : 'input',            //input, textarea
      build       : 'append',           //append, overwrite
      startImg    : 'mic.gif',
      animateImg  : 'mic-animate.gif',
      errorImg    : 'mic-slash.gif',
    };

    /***********************
    //General Configuring (Global Variables)
    ***********************/

    // get the defaults or any user set options
    var settings = $.extend(defaultSettings, instanceSettings);

    var obj = this;
    var final_transcript = '';
    var recognizing = false;
    var ignore_onend;
    var start_timestamp;

    if (!('webkitSpeechRecognition' in window)) {
      upgrade();
    } 
    else {
      //set a unique ID for the webSpeech instance
      var id = (window.webSpeechID) ? parseInt(window.webSpeechID + 1) : 1;
      window.webSpeechID = id;

      //START: Configure the button
      if ($('#'+settings.button).length == 0) {
        console.log('No button found for initiating webSpeech');
        return;
      }
      else {
        $('#'+settings.button).click(function() {
          webSpeech_startButton(id, event);
        });
        $('#'+settings.button).html('<img id="webSpeech_'+ id +'_img_mic" src="'+ settings.startImg +'" alt="Start">');
      }
      //END: Configure the button

      //START: recognition
      var recognition = new webkitSpeechRecognition();
      recognition.interimResults = false;

      recognition.onstart = function() {
        console.log('start');
        recognizing = true;
        ignore_onend = false;
        $('#webSpeech_'+ id +'_img_mic').attr('src', settings.animateImg);
      };

      recognition.onerror = function(event) {
        console.log('error');
        $('#webSpeech_'+ id +'_img_mic').attr('src', settings.startImg);
        ignore_onend = true;
        recognizing = false;
        if (event.error == 'no-speech') {
          
        }
        if (event.error == 'audio-capture') {

        }
        if (event.error == 'not-allowed') {
          if (event.timeStamp - start_timestamp < 100) {
            //showInfo(id, 'info_blocked');
          }
          else {
            //showInfo(id, 'info_denied');
          }
        }
      };

      recognition.onend = function() {
        console.log('end');
        recognizing = false;
        if (ignore_onend) {
          return;
        }
        $('#webSpeech_'+ id +'_img_mic').attr('src', settings.startImg);

        //add web speech text to our element
        switch(settings.build) {
          case"append":
            if (settings.format == 'input' || settings.format == 'textarea') {
              obj.val(final_transcript);
            }
            else {

            }
            break;
          case"overwrite":
            if (settings.format == 'input') {
              obj.val(final_transcript);
            }
            else {

            }
            break;
        }
      };

      recognition.onresult = function(event) {
        console.log('result');
        final_transcript = '';
        for (var i = event.resultIndex; i < event.results.length; ++i) {
          if (event.results[i].isFinal) {
            final_transcript += event.results[i][0].transcript;
          }
        }
        console.log(final_transcript);
      };
      //END: recognition
    }

    /*******************
    * HELPER FUNCTIONS
    *******************/

    function upgrade() {
      $('#webSpeech_'+ id +'_btn_mic').hide();
    }

    function webSpeech_startButton(id,event) {
      if (recognizing) {
        recognition.stop();
        return;
      }
      final_transcript = '';
      recognition.lang = settings.lang;
      recognition.continuous = settings.continuous;
      recognition.start();
      ignore_onend = false;
      $('#webSpeech_'+ id +'_final_span').html('');
      $('#webSpeech_'+ id +'_interim_span').html('');
      $('#webSpeech_'+ id +'_img_mic').attr('src', settings.errorImg);

      start_timestamp = event.timeStamp;
    }

  }
  //END $.fn.webSpeech

})(jQuery)
