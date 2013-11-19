//= require js/jquery/jquery.calendarEvents.js
//= require js/relations/menu.js

/*global ContextualPopup, Hourglass */

/**
 * @author Valeriy Vasin (valeriy.vasin@sup.com)
 * @description Controlstrip functionality
 */

;(function ($) {
  'use strict';

  // currently in IE8 when documentMode IE7 Standards is ON, some stuff is not working properly (e.g. ng-class)
  // Use fallback for that browser. Angular functionality should be turned off
  var IE7mode = Boolean(typeof document.documentMode !== 'undefined' && document.documentMode < 8);

  /**
   * Add community filter functionality for control strip
   */
  function initFilter() {
    var bubble,
        form,
        input,
        submit;

    // filter is available only for logged in users
    if ( !LJ.get('remoteUser') ) {
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

    if ( LJ.Flags.isEnabled('friendsAndSubscriptions') && !IE7mode ) {
      // init angular
      angular.bootstrap( $('[data-controlstrip]'), ['Relations.Menu']);
    }

    // calendar
    (function initCalendar() {
      var calendarLink = $('#lj_controlstrip_new .w-cs-i-calendar a'),

          // checks if we are on /friends page or not. There special calendar behavior is needed
          journalViewFriends = /^\/friends\/?$/.test( location.pathname ),
          journalUrlBase = LJ.get('current_journal.url_journal'),

          earlyDate = LJ.get('controlstrip.calendar.earlyDate'),
          lastDate  = LJ.get('controlstrip.calendar.lastDate');

      if ( calendarLink.length ) {
        calendarLink
          .calendar({
            showOn: 'click',
            closeControl: false,

            dayRef:  journalUrlBase + '/' + (journalViewFriends ? 'friends/' : '') + '%Y/%M/%D',
            allRefs: journalViewFriends,

            startMonth: earlyDate ? parseDate( LJ.get('controlstrip.calendar.earlyDate') ) : new Date(),
            endMonth:   lastDate  ? parseDate( LJ.get('controlstrip.calendar.lastDate') )  : new Date(),

            classNames: {
              container: 'w-cs-calendar'
            },

            ml: {
              caption: LJ.ml('web.controlstrip.view.calendar')
            }
          })
          .on('daySelected', function (event) {
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

    $('.b-loginpopup').bubble({
      target: '.i-auth-control',
      closeControl: false,
      showOn: 'click'
    });

    $('input.text').labeledPlaceholder();
  }

  $(function () {

    // load control strip if it's not available on document ready
    // Notice: some s2 users could turn off control strip for all users
    if (!document.getElementById('lj_controlstrip') && !document.getElementById('lj_controlstrip_new')) {
      // fetch control strip from server
      $.get(
        LiveJournal.getAjaxUrl('controlstrip'),
        { user: LJ.get('currentJournal') },
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
