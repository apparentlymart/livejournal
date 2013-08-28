//= require js/jquery/jquery.calendarEvents.js
//= require js/jquery/jquery.lj.relations.js
//= require js/lib/angular.min.js
//= require js/core/angular/common.js
//= require js/core/angular/bubble.js

//= require js/settings/services/filters/filters.js
//= require js/settings/services/filters/users.js

//= require_template angular/controlstrip/friend.ng.tmpl
//= require_template angular/controlstrip/join.ng.tmpl
//= require_template angular/controlstrip/subscribe.ng.tmpl
//= require_template angular/controlstrip/subscribeCommunity.ng.tmpl
//= require_template angular/controlstrip/filters.ng.tmpl

/*global ContextualPopup */
/**
 * @author Valeriy Vasin (valeriy.vasin@sup.com)
 * @description Control strip functionality
 */

angular.module('Controlstrip',
  ['LJ.Templates', 'LJ.Bubble', 'GroupsAndFilters.Services.Filters'],
  ['$locationProvider', function ($locationProvider) {
    $locationProvider.html5Mode(true);
  }])
  .controller('ControlstripCtrl', ['$scope', 'Bubble', function ($scope, Bubble) {
    var isCommunity = Boolean( LJ.get('current_journal.is_comm') );

    LiveJournal.register_hook('relations.changed', function (event) {
      switch (event.action) {
        case 'addFriend':
          Bubble.open('friend');
          break;
        case 'subscribe':
          Bubble.open(isCommunity ? 'subscribeCommunity' : 'subscribe');
          break;
        case 'join':
          Bubble.open('join');
          break;
      }
      $scope.$apply();
    });

    // Bubble.current = 'friend';
  }])
  .controller('FiltersCtrl', function ($scope, Filter) {
    Filter.fetch()
      .then(function (data) {
        $scope.filters = data;
      });
  });

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
      $('[data-relations]').relations();

      LiveJournal.register_hook('relations.changed', function (event) {
        var data = event.data,
          status = null;

        if (data.controlstrip_status) {
          status = $('.js-controlstrip-status');

          // Hide contextual popup before
          // If you're trying to change status from contextual popup in control strip
          if ( ContextualPopup.currentElement === status.find('.ljuser img').get(0) ) {
            ContextualPopup.hide();
          }

          status
            .html(data.controlstrip_status);
        }
      });

      // init angular
      angular.bootstrap( $('[data-controlstrip]'), ['Controlstrip']);
    }

    // calendar
    (function () {
      var calendarLink = $('#lj_controlstrip_new .w-cs-i-calendar a'),
          journalViewFriends = Boolean( LJ.get('controlstrip.calendar.journal_view_friends') ),
          journalUrlBase = LJ.get('controlstrip.calendar.journal_url_base');

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
