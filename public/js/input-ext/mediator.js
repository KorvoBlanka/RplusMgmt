/**
Mediator editable input.
Internally value stored as {name: "Agent", phone_num: "9141111111"}
**/

$(function () {
    var Mediator = function (options) {
        this.init('mediator', options, Mediator.defaults);
    };

    //inherit from Abstract input
    $.fn.editableutils.inherit(Mediator, $.fn.editabletypes.abstractinput);

    $.extend(Mediator.prototype, {
        /**
        Renders input from tpl
        
        @method render() 
        **/
        render: function() {
           this.$input = this.$tpl.find('input');
        },

        /**
        Default method to show value in element. Can be overwritten by display option.
        
        @method value2html(value, element) 
        **/
        value2html: function(value, element) {
            if(!value) {
                $(element).empty();
                return;
            }
            //var html = $('<div>').text(value.name).html() + ', ' + $('<div>').text(value.phoneNum).html();
            var html = $('<div>').text(value.phoneNum).html();
            $(element).html(html); 
        },

        /**
        Gets value from element's html
        
        @method html2value(html) 
        **/
        html2value: function(html) {
          /*
            you may write parsing method to get value by element's html
            e.g. "Agent, 9141111111" => {name: "Agent", phoneNum: "9141111111"}
            but for complex structures it's not recommended.
            Better set value directly via javascript, e.g. 
            editable({
                value: {
                    name: "Agent",
                    phoneNum: "9141111111"
                }
            });
          */
          return null;
        },

        /**
         Converts value to string. 
         It is used in internal comparing (not for sending to server).
         
         @method value2str(value)  
        **/
        value2str: function(value) {
            var str = '';
            if(value) {
                for(var k in value) {
                    str = str + k + ':' + value[k] + ';';
                }
            }
            return str;
        },

        /*
         Converts string to value. Used for reading value from 'data-value' attribute.
         
         @method str2value(str)  
        */
        str2value: function(str) {
            /*
            this is mainly for parsing value defined in data-value attribute. 
            If you will always set value by javascript, no need to overwrite it
            */
            return str;
        },

        /**
         Sets value of input.
         
         @method value2input(value) 
         @param {mixed} value
        **/
        value2input: function(value) {
             if (value) {
                 this.$input.filter('[name="name"]').val(value.name);
                 this.$input.filter('[name="phone_num"]').val(value.phoneNum);
             }
        },

        /**
         Returns value of input.
         
         @method input2value() 
        **/
        input2value: function() { 
            return {
               name: this.$input.filter('[name="name"]').val(), 
               phoneNum: this.$input.filter('[name="phone_num"]').val(), 
            };
        },

        /**
        Activates input: sets focus on the first field.
        
        @method activate()
        **/
        activate: function() {
             this.$input.filter('[name="name"]').focus();
             //this.$input.filter('[name="phone_num"]').focus();
        },

        /**
         Attaches handler to submit form in case of 'showbuttons=false' mode
         
         @method autosubmit() 
        **/
        autosubmit: function() {
            this.$input.keydown(function (e) {
                 if (e.which === 13) {
                     $(this).closest('form').submit();
                 }
            });
        }
    });

    Mediator.defaults = $.extend({}, $.fn.editabletypes.abstractinput.defaults, {
        tpl: '<div class="editable-mediator"><label><span>Name: </span><input type="text" name="name" class="input-small"></label></div>' +
             '<div class="editable-mediator"><label><span>PhoneNum: </span><input type="text" name="phone_num" class="input-small" readonly></label></div>',
        inputclass: ''
    });

    $.fn.editabletypes.mediator = Mediator;

});
