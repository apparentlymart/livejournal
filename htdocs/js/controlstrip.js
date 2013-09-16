//= require js/jquery/jquery.calendarEvents.js

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

//= require_template angular/controlstrip/controlstrip.ng.tmpl
//= require js/core/angular/ljUserDynamic.js


/*global ContextualPopup, Hourglass */

/**
 * @author Valeriy Vasin (valeriy.vasin@sup.com)
 * @description Control strip functionality
 */

;(function ($) {

angular.module('Controlstrip',
  ['LJ.Templates', 'LJ.Bubble', 'LJ.Directives', 'LJ.User', 'GroupsAndFilters.Services.Filters', 'GroupsAndFilters.Services.Users'],
  ['$locationProvider', function ($locationProvider) {
    $locationProvider.html5Mode(true);
  }])
  .controller('RelationsCtrl', ['$scope', 'Bubble', '$timeout', '$q',
                         function ( $scope,   Bubble,   $timeout,   $q ) {

    var status = $('.w-cs-status'),
        username = LJ.get('current_journal.username'),
        _hourglass;

    // need it in scope to show lj-user-dynamic
    $scope.username = username;

    // relation states
    $scope.states = {
      isFriend: Boolean( LJ.get('remote.is_friend') ),
      isMember: Boolean( LJ.get('remote.is_member') ),
      isSubscribed: Boolean( LJ.get('remote.is_subscribedon') )
    };
    $scope.status = LJ.get('remote.status');

    // update states
    LJ.Event.on('relations.changed', function (event) {
      var data = event.data;

      // Hide contextual popup if we are changing status from contextual popup
      // in control strip.
      if ( ContextualPopup.currentElement === status.find('.ljuser img').get(0) ) {
        ContextualPopup.hide();
      }

      $timeout(function () {
        $scope.status = data.controlstrip_status;

        $scope.states.isFriend     = Boolean(data.is_friend);
        $scope.states.isMember     = Boolean(data.is_member);
        $scope.states.isSubscribed = Boolean(data.is_subscribedon);
      });
    });

    function changeRelation(action, $event) {
      var defer = $q.defer();

      if ($event) {
        showHourglass($event);
      }

      LJ.Event.trigger('relations.change', {
        action: action,
        username: username,
        callback: function () {
          hideHourglass();
          $timeout(defer.resolve);
        }
      });

      return defer.promise;
    }

    $scope.subscribe = function ($event) {
      $event.preventDefault();
      changeRelation('subscribe', $event)
        .then(function () {
          $scope.mode = 'subscribe';
          Bubble.open('controlstrip', 'unsubscribe');
        });
    };

    $scope.unsubscribe = function ($event) {
      $event.preventDefault();
      changeRelation('unsubscribe', $event);
    };

    $scope.addFriend = function ($event) {
      $event.preventDefault();
      changeRelation('addFriend', $event)
        .then(function () {
          $scope.mode = 'add';
          Bubble.open('controlstrip', 'removeFriend');
        });
    };

    $scope.removeFriend = function ($event) {
      $event.preventDefault();
      changeRelation('removeFriend', $event);
    };

    $scope.watch = function ($event) {
      $event.preventDefault();
      changeRelation('subscribe', $event)
        .then(function () {
          $scope.mode = 'watch';
          Bubble.open('controlstrip', 'unsubscribe');
        });
    };

    $scope.unwatch = function ($event) {
      $event.preventDefault();
      changeRelation('unsubscribe', $event);
    };

    $scope.join = function ($event) {
      $event.preventDefault();
      changeRelation('join', $event)
        .then(function () {
          $scope.mode = $scope.states.isSubscribed ? 'joinSubscribed' : 'join';
          Bubble.open('controlstrip', 'leave');
        });
    };

    $scope.leave = function ($event) {
      $event.preventDefault();
      changeRelation('leave', $event);
    };

    /**
     * Subscribe to community updates in a bubble after join action
     */
    $scope.subscribeAfterJoin = function () {
      $scope.loading = true;

      changeRelation('subscribe')
        .then(function () {
          $scope.loading = false;
          $scope.mode = 'watch';
        });
    };

    /**
     * Show hourglass for event
     *
     * @param  {jQuery.Event} event jQuery event (click)
     */
    function showHourglass(event) {
      if (_hourglass) {
        hideHourglass();
      }

      _hourglass = new Hourglass().setEvent(event).show();
    }

    /**
     * Hide hourglass
     */
    function hideHourglass() {
      if (_hourglass) {
        _hourglass.remove();
        _hourglass = null;
      }
    }
  }])
  .controller('FiltersCtrl', ['$scope', '$q', 'Filter', 'FilterUsers',
                    function ( $scope,   $q,   Filter,   FilterUsers) {

    var filtersPromise = Filter.fetch({ cache: true }),
        usersPromise   = FilterUsers.fetch({ cache: true }),
        username = LJ.get('current_journal.username'),
        user;

    $scope.model = {
      newFilter: '',
      showCreateDialog: false
    };

    $scope.loading = false;

    $q.all({ filters: filtersPromise, users: usersPromise })
      .then(function (result) {
        var filters = result.filters;

        user = FilterUsers.getUser(username);

        $scope.filters = filters;
      });

    /**
     * Toggle filter state
     */
    $scope.toggleFilter = function (id, state) {
      if (state) {
        FilterUsers.addToGroup(id, [username]);
      } else {
        FilterUsers.removeFromGroup(id, [username]);
      }
    };

    $scope.isActive = function (id) {
      var isActive = FilterUsers.isUserInGroup(username, id);
      return isActive;
    };

    $scope.createFilter = function () {
      var name = $scope.model.newFilter.trim();

      $scope.resetFilter();

      if ( name.length !== 0 ) {
        Filter.create(name)
          .then(function (response) {
            var filter = response.filter;

            FilterUsers.addToGroup(filter.id, [username]);
          });
      }
    };

    $scope.resetFilter = function () {
      $scope.model.newFilter = '';
      $scope.model.showCreateDialog = false;
    };
  }]);

}(jQuery));

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
