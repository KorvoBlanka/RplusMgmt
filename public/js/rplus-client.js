/**
 *
 * Rplus Client Widget
 *
 */

(function($) {
    $('html').on('mouseup', function(e) {
        if (!$(e.target).closest('.popover').length && !$(e.target).closest('.rplus-client').length) {
            $('.popover').each(function() {
                $(this.previousSibling).popover('hide');
            });
        }
    });

    $.fn.rplusClient = function (options, val) {
        var widget = this;

        function drawWidget() {
            var value = widget.data('value');
            if (value) {
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
                xhtml += '</div>';
                widget.html(xhtml); 
            } else {
                widget.html('<span class="rplus-client-empty">Empty</span>');
            }
        }

        if (typeof options === 'object' || !options) {
        } else if (options == 'setValue') {
            widget.data('value', val);
            drawWidget();
            return this;
        } else if (options == 'getValue') {
            return widget.data('value');
        }

        if (!options.formId) {
            alert('Error while initializing rplusClient widget');
            return this;
        }

        var formId = options.formId;
        var content =
            '<form class="form-horizontal" id="' + options.formId + '" style="margin-bottom: 0px;">' +
            '<div class="control-group">' +
                '<label class="control-label" style="width:auto;">Name:</label>' +
                '<div class="controls" style="margin-left:80px;">' +
                    '<input type="text" name="name" class="input-medium" placeholder="Имя клиента" autocomplete="off">' +
                    '<button type="submit" class="btn btn-primary" style="margin-left: 7px;"><i class="icon-ok icon-white"></i></button>' +
                    '<button type="button" class="btn" style="margin-left: 7px;"><i class="icon-remove"></i></button>' +
                    '<button type="button" class="btn btn-danger" style="margin-left: 7px; position: absolute; right: 15px; top:82px;"><i class="icon-trash icon-white"></i></button>' +
                '</div>' +
            '</div>' +
            '<div class="control-group" style="margin-bottom: 5px !important;">' +
                '<label class="control-label" style="width:auto;">Phones:</label>' +
                '<div class="controls" style="margin-left:80px;">' +
                    '<input type="tel" name="phone_num[]" class="input-small" pattern="^([0-9]{6,7})|([0-9]{10})$" placeholder="9xxxxxxxxx" autocomplete="off" required>' +
                '</div>' +
            '</div>' +
            '<div class="control-group" style="margin-bottom: 5px !important;">' +
                '<label class="control-label" style="width:auto;"></label>' +
                '<div class="controls" style="margin-left:80px;">' +
                    '<input type="tel" name="phone_num[]" class="input-small" pattern="^([0-9]{6,7})|([0-9]{10})$" placeholder="xxxxxx" autocomplete="off">' +
                '</div>' +
            '</div>' +
            '<div class="control-group" style="margin-bottom: 5px !important;">' +
                '<label class="control-label" style="width:auto;"></label>' +
                '<div class="controls" style="margin-left:80px;">' +
                    '<input type="tel" name="phone_num[]" class="input-small" pattern="^([0-9]{6,7})|([0-9]{10})$" autocomplete="off">' +
                '</div>' +
            '</div>' +
            '</form>'
        ;

        widget.popover({
            placement: options.placement || 'right',
            title: options.title || 'Enter client info',
            html: true,
            content: content,
            trigger: 'manual',
        });

        widget.click(function (event) {
            widget.popover('toggle');
            if ($('.popover:visible').length) {
                // form submitting
                $('#' + formId).submit(function (event) {
                    var value = widget.data('value') || {};
                    value.name = $('input[name="name"]', $(this)).val();
                    value.contact_phones = [];
                    $('input[type="tel"]', $(this)).each(function (i, el) {
                        if ($(el).val()) {
                            value.contact_phones.push($(el).val());
                        }
                    });
                    widget.data('value', value);
                    drawWidget();
                    widget.popover('hide');
                    return false;
                });
                // close button
                $('#' + formId + ' button:eq(1)').click(function (event) {
                    widget.popover('hide');
                });
                // trash button
                $('#' + formId + ' button:eq(2)').click(function (event) {
                    widget.data('value', null);
                    drawWidget();
                    widget.popover('hide');
                });

                // Update values
                var value = widget.data('value');
                if (value) {
                    $('#' + formId + ' input[name="name"]').val(value.name || '');
                    $.each(value.contact_phones, function (i, el) {
                        $('#' + formId + ' input[type="tel"]:eq(' + i + ')').val(el);
                    });
                } else {
                    $('#' + formId + ' input').val('');
                }

                $('.popover:visible input[type="tel"]:eq(0)').focus();
            }
        });

        drawWidget();

        return widget;
    };
})(jQuery);
