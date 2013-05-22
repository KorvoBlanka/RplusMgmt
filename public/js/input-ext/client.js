/**
Client editable input.
Internally value stored as {name: "Agent", phone_num: "9141111111"}
**/

$(function () {
    var Client = function (options) {
        this.init('client', options, Client.defaults);
    };

    //inherit from Abstract input
    $.fn.editableutils.inherit(Client, $.fn.editabletypes.abstractinput);

    $.extend(Client.prototype, {
        /**
        Renders input from tpl
        
        @method render() 
        **/
        render: function() {
           this.$input = this.$tpl.find('input');
           this.$clear = this.$tpl.find('.editable-clear');
        },

        postrender: function () {
            this.$clear.click($.proxy(function (event) {
                this.clear();
                this.$clear.closest('form').submit();
            }, this));
        },

        /**
        Default method to show value in element. Can be overwritten by display option.
        
        @method value2html(value, element) 
        **/
        value2html: function(value, element) {
            if (!value) {
                $(element).empty();
                return;
            }
            var xname = $('<div>').text(value.name).html();
            var xphones = $('<div>').text(value.contact_phones.join(', ')).html();
            var xhtml = '<div class="alert alert-info">';
            if (value.name) {
                xhtml += xname + ' (';
            }
            xhtml += xphones;
            if (value.name) {
                xhtml += ')';
            }
            //xhtml += '<button type="button" class="close" style="top: -7px; right: -29px;">&times;</button>';
            xhtml += '</div>';
            $(element).html(xhtml); 
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
            var el_phones = this.$input.filter('[type="tel"]:input');
            if (value) {
                this.$input.filter('[name="id"]').val(value.id);
                this.$input.filter('[name="name"]:input').val(value.name);
                $.each(value.contact_phones, function (i, el) {
                    el_phones.eq(i).val(el);
                });
            }
        },

        /**
         Returns value of input.
         
         @method input2value() 
        **/
        input2value: function() {
            var id = this.$input.filter('[name="id"]:input').val();
            var name = this.$input.filter('[name="name"]:input').val();
            var contact_phones = [];
            this.$input.filter('[type="tel"]:input').each(function (i, el) {
                if ($(el).val()) {
                    contact_phones.push($(el).val());
                }
            });
            return {
                id: id,
                name: name,
                contact_phones: contact_phones
            };
        },

        /**
        Activates input: sets focus on the first field.
        
        @method activate()
        **/
        activate: function() {
            this.$input.filter('input[type="tel"]:eq(0)').focus();
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

    Client.defaults = $.extend({}, $.fn.editabletypes.abstractinput.defaults, {
        tpl: '' +
             '<div class="editable-client"><input type="hidden" name="id" value=""><label><span>Name:</span><input type="text" name="name" class="input-medium" placeholder="Имя клиента" autocomplete="off"></label></div>' +
             '<div class="editable-client editable-client-phone"><label><span>Phones:</span><input type="tel" name="phone_num[]" class="input-small" pattern="^([0-9]{6,7})|([0-9]{10})$" placeholder="9xxxxxxxxx" autocomplete="off" required></label></div>' +
             '<div class="editable-client editable-client-phone"><label><span></span><input type="tel" name="phone_num[]" class="input-small" pattern="^([0-9]{6,7})|([0-9]{10})$" placeholder="xxxxxx" autocomplete="off"></label></div>' +
             '<div class="editable-client editable-client-phone"><label><span></span><input type="tel" name="phone_num[]" class="input-small" pattern="^([0-9]{6,7})|([0-9]{10})$" autocomplete="off"></label></div>' +
             '<div style="position: absolute; right: 14px; top:82px; "><button type="button" class="btn btn-danger editable-clear"><i class="icon-trash icon-white"></i></button></div>',
        inputclass: ''
    });

    $.fn.editabletypes.client = Client;

});
