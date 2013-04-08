/*global LJWidgetIPPU_SelectTags */
;(function ($) {
    'use strict';

    function initSelectTagsWidget() {
        var user = LiveJournal.parseGetArgs().authas,
            _window = $(window),
            authForm = $('#authForm [name=authas]');

        $('.js-select-tags-widget').on('click', function (e) {
            var widget;

            e.preventDefault();

            widget = new LJWidgetIPPU_SelectTags(
                {
                    title: $(this).text(),
                    height: 329,
                    width: _window.width() / 2
                },
                {
                    user: user || authForm.val()
                }
            );
        });

    }

    $(function () {
        initSelectTagsWidget();
    });
}(jQuery));

