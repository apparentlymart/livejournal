//= require js/jquery/jquery.calendarEvents.js
//= require js/relations/menu.js

/*global ContextualPopup, Hourglass */

/**
 * @author Valeriy Vasin (valeriy.vasin@sup.com)
 * @description Controlstrip functionality
 */

;(function ($) {
  'use strict';

  /**
   * Add community filter functionality for control strip
   */
  function initFilter() {
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
   * Initialize control strip
   */
  function init() {
    initFilter();
    addLabledPlaceholders();

    if ( LJ.Flags.isEnabled('friendsAndSubscriptions') ) {
      // init angular
      angular.bootstrap( $('[data-controlstrip]'), ['Relations.Menu']);
    }

    // calendar
    (function () {
      var calendarLink = $('#lj_controlstrip_new .w-cs-i-calendar a'),

          // checks if we are on /friends page or not. There special calendar behavior is needed
          journalViewFriends = /^\/friends\/?$/.test( location.pathname ),
          journalUrlBase = LJ.get('current_journal.url_journal');

      if ( calendarLink.length ) {
        calendarLink
          .calendar({
            showOn: 'click',
            closeControl: false,

            dayRef:  journalUrlBase + '/' + (journalViewFriends ? 'friends/' : '') + '%Y/%M/%D',
            allRefs: journalViewFriends,

            startMonth: parseDate( LJ.get('controlstrip.calendar.earlyDate') ),
            endMonth:   parseDate( LJ.get('controlstrip.calendar.lastDate') ),

            classNames: {
              container: 'w-cs-calendar'
            },

            ml: {
              caption: LJ.ml('web.controlstrip.view.calendar')
            }
          })
          .bind('daySelected', function (event) {
            event.preventDefault();
          });

          if ( !journalViewFriends ) {
            calendarLink.calendarEvents( { fetchOnFirstDisplay: true } );
          }
      }

      /**
       * Convert string e.g. "2009,10,27" to Date object
       * @return {Date} Parsed Date
       */
      function parseDate(str) {
        var date = str.split(',').map(Number);

        return new Date(date[0], date[1], date[2]);
      }
    }());
  }

  $(function () {
    // load control strip if it's not available on document ready
    // Notice: some s2 users could turn off control strip for all users
    if (!document.getElementById('lj_controlstrip') && !document.getElementById('lj_controlstrip_new')) {
      // fetch control strip from server
      $.get(
        LiveJournal.getAjaxUrl('controlstrip'),
        { user: Site.currentJournal },
        function (data) {
          $(data).appendTo(document.body);
          init();
        }
      );
    } else {
      init();
    }
  });

}(jQuery));
