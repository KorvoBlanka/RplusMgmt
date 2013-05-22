/**
 * Rplus Request Line
 *
 * Options:
 *   url
 *   profile,
 *   placeholder
 * 
 * Events:
 *   queryChanged
 */

(function($) {
    $.fn.requestLine = function (options, val) {
        var $this = this;

        var settings,
            requestLine, requestLinePlaceholder,
            canAutoSelect = false,
            readyAutoSelect = false
        ;

        if (typeof options === 'object' || !options) {
            // normal initialization
        } else if (options == 'query') {
            return $this.data('query');
        } else if (options == 'val') {
            if (val === undefined) {
                return $this.data('query');
            } else {
                var items = val || [];
                var query = {};
                var requestText = '';
                for (var i = 0; i < items.length; i++) {
                    var item = items[i];
                    if (!query[item.field]) query[item.field] = new Array();
                    query[item.field].push(item.value);
                    requestText = requestText + item.label + ', ';
                }
                $this.data('items', items);
                $this.data('query', query);
                $this.val(String.fromCharCode(35)).val(requestText);
                $this.data('pos', $this.val().length)
                return;
            }
        }

        settings = $.extend({
            delay: 50,
            width: '30%',
        }, options);

        $this.data('items', []);
        $this.data('query', {});
        $this.data('pos', 0);
        requestLine = $this;
        requestLinePlaceholder = settings.placeholder;

        requestLine.autocomplete({
            delay: settings.delay,
            minLength: 1,
            autoFocus: true,
            source: function (request, response) {
                var query = $this.data('query');
                var term = requestLine.val().substring($this.data('pos'));
                var j = $.getJSON(settings.url, {term:term, subquery: JSON.stringify(query), profile: settings.profile}, response);
                j.done(function (data) {
                    if (data.length == 1 && term && !term.match(/^\d+$/)) {
                        canAutoSelect = true;
                    } else {
                        canAutoSelect = false;
                    }
                    if (data.length >= 1) {
                        var term = requestLine.val().substring($this.data('pos'));
                        var label = data[0].label;
                        if (label.substring(0, term.length).toLowerCase() == term.toLowerCase()) {
                            if (requestLinePlaceholder) {
                                requestLinePlaceholder.val(requestLine.val() + label.substring(term.length));
                            }
                        } else {
                            if (requestLinePlaceholder) {
                                requestLinePlaceholder.val('');
                            }
                        }
                    }
                });
                return j;
            },
            search: function (event, ui) { // before search
                var term = requestLine.val().substring($this.data('pos'));
                if (term.length < 1) {
                    requestLine.autocomplete('close');
                    return false; // prevent search
                }
                return true;
            },
            focus: function (event, ui) {
                var term = requestLine.val().substring($this.data('pos'));
                var label = ui.item.label;
                if (label.substring(0, term.length).toLowerCase() == term.toLowerCase()) {
                    if (requestLinePlaceholder) {
                        requestLinePlaceholder.val(requestLine.val() + label.substring(term.length));
                    }
                } else {
                    if (requestLinePlaceholder) {
                        requestLinePlaceholder.val('');
                    }
                }
                return false; // prevent replace the text field's value with the value of the focused item
            },
            select: function (event, ui) {
                var item = {label: ui.item.label, field: ui.item.value.field, value: ui.item.value.value};

                var items = $this.data('items');
                var query = $this.data('query');
                items.push(item);
                if (!query[item.field]) query[item.field] = new Array();
                query[item.field].push(item.value);
                //$this.data('items', items);
                //$this.data('query', query); // necessarily?

                var requestText = '';
                for (var i = 0; i < items.length; i++) {
                    requestText = requestText + items[i].label + ', ';
                }
                requestLine.focus().val(String.fromCharCode(35)).val(requestText);
                if (requestLinePlaceholder) {
                    requestLinePlaceholder.val('');
                }
                $this.data('pos', requestLine.val().length);
                requestLine.trigger('queryChanged', [query]);

                return false;
            },
            open: function () {
                $(this).autocomplete('widget').css('z-index', 100);
                $(this).autocomplete('widget').css('width', settings.width);
                return false;
            },
            close: function (event, ui) {
                if (requestLinePlaceholder) {
                    requestLinePlaceholder.val('');
                }
            }
        });
        requestLine.click(function (event) {
            var x = requestLine.val();
            requestLine.focus().val(String.fromCharCode(35)).val(x);
            if (requestLinePlaceholder) {
                requestLinePlaceholder.val('');
            }
        });
        requestLine.keypress(function (event) {
            if (requestLinePlaceholder) {
                var newText = requestLine.val() + String.fromCharCode(event.charCode);
                var subPlaceholder = requestLinePlaceholder.val().substring(0, newText.length);
                if (newText.toLowerCase() != subPlaceholder.toLowerCase()) {
                    requestLinePlaceholder.val('');
                }
            }
        });
        requestLine.keydown(function (event) {
            if (event.keyCode == 37 || event.keyCode == 39 || event.keyCode == 36) {  // leftArrow && rightArrow && Home
                event.preventDefault();
            } else if (event.keyCode === $.ui.keyCode.BACKSPACE) { // Backspace
                if ($this.data('pos') == requestLine.val().length) {
                    var items = $this.data('items');
                    if (items.length > 0) {
                        var item = items.pop();
                        var query = $this.data('query');
                        query[item.field].pop();
                        if (query[item.field].length == 0) delete query[item.field];
                        //$this.data('items', items);
                        //$this.data('query', query); // necessarily?

                        var requestText = '';
                        for (var i = 0; i < items.length; i++) {
                            requestText = requestText + items[i].label + ', ';
                        }
                        requestLine.focus().val(String.fromCharCode(35)).val(requestText);
                        if (requestLinePlaceholder) {
                            requestLinePlaceholder.val('');
                        }
                        $this.data('pos', requestLine.val().length);
                        requestLine.trigger('queryChanged', [query]);
                    }
                    event.preventDefault();
                }
            } else {
                readyAutoSelect = false;
            }
        });

        return requestLine;
    };
})(jQuery);
