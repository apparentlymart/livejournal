LiveJournal.register_hook('init_settings', function ($) {
	$('.b-settings-apps-item-name').click(function () {
		$(this).parent().toggleClass('b-settings-apps-item-open');
	});
});

LiveJournal.register_hook('init_settings', function ($) {
	var Settings = {
		confirm_msg: LiveJournal.getLocalizedStr('.form.confirm', null, 'Save your changes?'),
		form_changed: false,
		navclickSave: function(e) {
			if (!Settings.form_changed || e.isDefaultPrevented()) {
				return;
			}

			var confirmed = confirm(Settings.confirm_msg);
			confirmed && Settings.$form.submit();
		}
	};

	Settings.$form = $('#settings_form');
	if (!Settings.$form.length) {
		return;
	}
	// delegate onclick on all links to confirm form saving
	$(document).delegate('a', 'click', Settings.navclickSave);

	Settings.$form.delegate('select, input, textarea', 'change', function() {
		Settings.form_changed = true;
	});
});

LiveJournal.register_hook('init_settings', function ($) {
	var options = {
		selectors: {
			Trava: '#LJ__Setting__Music__Trava_',
			LastFM: '#LJ__Setting__Music__LastFM_',
			connectLink: '.music-settings-connect',
			uIdInput: 'input name="LJ__Setting__Music__Trava_trava_uid"'
		},
		classNames: {
			login: 'music-settings-login',
			logout: 'music-settings-logout',
			loading: 'music-settings-loading'
		},
		url: {
			trava: 'http://trava.ru/json/autologin'
		}
	};

	var travaElement = $(options.selectors.Trava);

	function onGetUserData(data) {
		travaElement
			.removeClass(options.classNames.loading)
			.addClass(data.uid == 1 ? options.classNames.logout : options.classNames.login);
		$(options.selectors.uIdInput).val(data.uid);
	}

	function errorGetUserData(data) {
		travaElement.removeClass(options.classNames.loading);
	}

	$('select[name="music_select"]').bind('change', function () {
		var currentID = '#' + $(this).val();
		var oldID = currentID == options.selectors.Trava ? options.selectors.LastFM : options.selectors.Trava;

		$(oldID).hide();
		$(currentID).show();
	});


	travaElement.delegate(options.selectors.connectLink, 'click', function (evt) {
		evt.preventDefault();
		travaElement.addClass(options.classNames.loading);
		$.ajax({
			url: options.url.trava,
			cache: false,
			dataType: 'jsonp',
			success: onGetUserData,
			error: errorGetUserData
		});
	});
});

LiveJournal.register_hook('page_load', function () {
	LiveJournal.run_hook('init_settings', jQuery);
});