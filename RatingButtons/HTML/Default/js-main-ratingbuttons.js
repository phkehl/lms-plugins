/*[%####################################################################################################################
#
# flipflip's RatingButtons plugin
#
# Copyright (c) 2021 Philippe Kehl (flipflip at oinkzwurgl dot org),
#
# This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public
# License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later
# version.
#
# This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied
# warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along with this program. If not, see
# <https://www.gnu.org/licenses/>.
#
####################################################################################################################%]*/

Ext.onReady(function() {

    [% INCLUDE plugins/RatingButtons/common.js %]

    // Monkey-patch into the playlist update function
    let origPlaylistOnUpdated = Main.playlist.onUpdated;
    Main.playlist.onUpdated = function ()
    {
        // Call original handler with its context
        origPlaylistOnUpdated.call(this);

        // Find our ratings markers and replace with a ratings display thingy
        document.querySelectorAll(
            '#' + this.playlistEl + ' .browsedbListItem .playlistSongDetail:nth-of-type(1) a span')
            .forEach(function (el)
        {
            let m = el.textContent.match(ratingExtractRe);
            if (m)
            {
                let stars   = parseInt(m[2]); // 0..5
                let trackId = parseInt(m[3]);
                // Put back all content but our "RATINGBUTTONS_RATING_WEB=<r>" marker
                el.textContent = m[1] + m[4];

                // Add HTML to title (next to the <a> title link), wrapped in a <div>
                let div = document.createElement('div');
                div.classList.add('ratingbuttons-rating-container');
                div.dataset.trackId = trackId;
                renderRating(div, stars);
                el.parentElement /* = a */ .parentElement /* = div */ .appendChild(div);
                
                // Handle clicks on on the rating thingy, respectively any of elements (stars, ..) within
                div.onclick = function (e) { updateRating(div, e); };
            }
        });
    };

    //SqueezeJS.Controller.on({
        // 'playlistchange': {
        //     fn: function (e)
        //     {
        //         console.log('ffi: playlistchange %o', [ e, this ]);
        //     },
        //     scope: this
        // },
        // 'playerstatechange': {
        //     fn: function (e)
        //     {
        //         console.log('ffi: playerstatechange %o', [ e, this ]);
        //     },
        //     scope: this
        // },
        // 'buttonupdate': {
        //     fn: function (e)
        //     {
        //         console.log('ffi: playerstatechange %o', [ e, this ]);
        //     },
        //     scope: this
        // },
    //});

    // Object.keys(window).forEach(key => {
    //     if (/^on/.test(key)) {
    //         window.addEventListener(key.slice(2), event => {
    //             console.log(event);
    //         });
    //     }
    // });

},
// Context
{
    clientId: "[% ratingbuttons.clientId %]"
});
