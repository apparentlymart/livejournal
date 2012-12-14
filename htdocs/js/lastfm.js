LJ.LastFM = {
    /*
     * @param {Object} data Last.fm response
     * @return {Object|null} Parsed object with "artist" and "title"
     */
    _parse: function(data) {
        'use strict';

        var tracks = data.recenttracks,
            last = tracks && tracks.track[0],
            date = null,
            justListened = false;

        if (last.name && last.artist && (last.artist.name || last.artist['#text'])) {

            if (last.date) {
                date = +new Date(Number(last.date.uts) * 1000),
                justListened = +new Date() - date < 300000;
            }

            if ((last['@attr'] && last['@attr'].nowplaying) || justListened) {
                return {
                    artist: last.artist.name || last.artist['#text'],
                    title: last.name,
                    _: last
                };
            } else {
                return null;
            }
        } else {
            throw new Error('Data error');
        }
    },

    /*
     * Get current playing (or just listened) track in last.fm
     * http://www.last.fm/api/show/user.getRecentTracks
     * @param {String} user LastFM username
     * @param {Function(Object)} callback Argument is the current track, see last.fm API
     */
    getNowPlaying: function(user, callback) {
        'use strict';

        var self = this;

        jQuery.ajax({
            url: 'http://ws.audioscrobbler.com/2.0/',
            dataType: 'jsonp',
            cache: false,
            data: {
                method: 'user.getrecenttracks',
                user: user,
                api_key: Site.page.last_fm_api_key,
                format: 'json'
            }
        }).done(function(res) {
            if (res.error) {
                console.error('Last.FM error: ' + res.message);
                return;
            }

            if (callback) {
                callback(
                    self._parse(res)
                );
            }
        });
    }
};

function lastfm_current ( username, show_error ) {
    'use strict';

    var user = Site.page.last_fm_user,
        label = null,
        input = document.getElementById('prop_current_music'),
        spinner = 'b-updatepage-field-music-loading';

    if (!user) {
        console.error('No last.fm user');
        return;
    }

    if (Site.page.ljpost) {
        label = jQuery('.b-updatepage-field-music');
        label.toggleClass(spinner, true);
        input.value = '';
    } else {
        input.value = 'Loading...';
    }

    LJ.LastFM.getNowPlaying(user, function(track) {
        if (track) {
            input.value = '{artist} - {title} | Powered by Last.fm'.supplant(track);
        } else {
            input.value = '';
        }

        if (label) {
            label.toggleClass(spinner, false);
        }
    });
}

if (Site.page.ljpost) {
    jQuery(function() {
        'use strict';

        if (Site.page.last_fm_user) {
            lastfm_current();
        }
    });
}
