/*global Hourglass */

/**
 * @author Valeriy Vasin (valeriy.vasin@sup.com)
 * @description Control strip functionality
 */
;(function ($) {
    'use strict';

    var Relations;

    /**
     * Add community filter functionality for control strip
     */
    function addFilterFunctionality() {
        var bubble,
            form,
            input,
            submit;

        // filter is available only for logged in users
        if ( !Site.remoteUser ) {
            return;
        }

        bubble = $('#lj_controlstrip_new .w-cs-filter-inner');

        // exit if filter content is not currently on the page
        if ( bubble.length === 0 ) {
            return;
        }

        form = $('#sortByPoster');
        input = form.find('[name=poster]');
        submit = form.find('[type=image]');

        bubble.bubble({
            target: '#lj_controlstrip_new .w-cs-filter-icon',
            showOn: 'click',
            closeControl: false
        });

        input.input(function () {
            if( this.value.length ) {
                submit.css('opacity', 1)
                    .prop('disabled', false);
            } else {
                submit.css('opacity', 0)
                    .prop('disabled', true);
            }
        });

        form.on('submit', function (e) {
            if( !input.val().length ) {
                e.preventDefault();
            }
        });
    }

    /**
     * Add labled placeholders for the control strip
     */
    function addLabledPlaceholders() {
        $('#lj_controlstrip_new input[placeholder]').labeledPlaceholder();
    }

    /**
     * Change relations from control strip
     */
    Relations = (function () {
        var selectors = {
                addFriend: '.controlstrip-menu-addfriend',
                removeFriend: '.controlstrip-menu-removefriend',
                subscribe: '.controlstrip-menu-subscribe',
                unsubscribe: '.controlstrip-menu-unsubscribe'
            },
            classNames = {
                // user is not friend and not subscribed
                notFriend: 'w-cs-menu-mode-default',
                friend: 'w-cs-menu-mode-friend',
                subscribed: 'w-cs-menu-mode-subscr'
            },
            allClasses = [
                classNames.subscribed,
                classNames.notFriend,
                classNames.friend
            ].join(' '),
            hourglass = null,
            username,
            container;

        function init() {
            username = Site.currentJournal;

            if (!username) {
                console.error('Can\'t detect current journal');
                return;
            }

            container = $('.w-cs-menu-friends-subscr');
            if (container.length === 0) {
                console.error('Controls strip container doesn\' exist');
                return;
            }

            bind();
            subscribe();
        }

        /**
         * Show hourglass on click
         * @param  {jQuery.Event} e jQuery event (click)
         */
        function showHourglass(e) {
            // hide previous hourglass if it's currently showed
            if (hourglass) {
                hideHourglass();
            }
            hourglass = new Hourglass().setEvent(e).show();
        }

        /**
         * Hide hourglass
         */
        function hideHourglass() {
            hourglass.remove();
            hourglass = null;
        }

        /**
         * Bind event listeners for controls strip
         */
        function bind() {
            container
                .on('click', selectors.addFriend, function (e) {
                    e.preventDefault();
                    showHourglass(e);
                    LiveJournal.run_hook('relations.addFriend', username);
                })
                .on('click', selectors.removeFriend, function (e) {
                    e.preventDefault();
                    showHourglass(e);
                    LiveJournal.run_hook('relations.removeFriend', username);
                })
                .on('click', selectors.subscribe, function (e) {
                    e.preventDefault();
                    showHourglass(e);
                    LiveJournal.run_hook('relations.subscribe', username);
                })
                .on('click', selectors.unsubscribe, function (e) {
                    e.preventDefault();
                    showHourglass(e);
                    LiveJournal.run_hook('relations.unsubscribe', username);
                });
        }

        /**
         * Subscribe for relation update events
         */
        function subscribe() {
            LiveJournal.register_hook('relations.addFriend.done', function () {
                hideHourglass();
                container
                    .removeClass( allClasses )
                    .addClass( classNames.friend );
            });

            LiveJournal.register_hook('relations.removeFriend.done', function () {
                hideHourglass();
                container
                    .removeClass( allClasses )
                    .addClass( classNames.notFriend );
            });

            LiveJournal.register_hook('relations.subscribe.done', function () {
                hideHourglass();
                container
                    .removeClass( allClasses )
                    .addClass( classNames.subscribed );
            });

            LiveJournal.register_hook('relations.unsubscribe.done', function () {
                hideHourglass();
                container
                    .removeClass( allClasses )
                    .addClass( classNames.notFriend );
            });
        }

        return {
            init: init
        };
    }());

    $(function () {
        // load control strip if it's not available on document ready
        // Notice: some s2 users could turn off control strip for all users
        if (!document.getElementById('lj_controlstrip') && !document.getElementById('lj_controlstrip_new')) {
            $.get(LiveJournal.getAjaxUrl('controlstrip'), { user: Site.currentJournal }, function (data) {
                    $(data).appendTo(document.body).ljAddContextualPopup();
                    addFilterFunctionality();
                    addLabledPlaceholders();
                    if ( LJ.Flags.isEnabled('friendsAndSubscriptions') ) {
                        Relations.init();
                    }
                }
            );
        } else {
            addLabledPlaceholders();
            addFilterFunctionality();
            if ( LJ.Flags.isEnabled('friendsAndSubscriptions') ) {
                Relations.init();
            }
        }
    });

}(jQuery));
