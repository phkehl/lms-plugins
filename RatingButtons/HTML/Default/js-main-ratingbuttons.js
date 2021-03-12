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


// Experiments.. not used..



// hmmm.... [% ratingbuttons.foo %]
Ext.onReady(function() {
    
    console.log('ready! %o', this);

    SqueezeJS.Controller.on({
        'playlistchange': {
            fn: function (e)
            {
                console.log('playlistchange %o', [ e, this ]);
                
            },
            scope: this
        },
        'playerstatechange': {
            fn: function (e)
            {
                console.log('playerstatechange %o', [ e, this ]);
                
            },
            scope: this
        },
        'buttonupdate': {
            fn: function (e)
            {
                console.log('playerstatechange %o', [ e, this ]);
                
            },
            scope: this
        },
    });
    // Object.keys(window).forEach(key => {
    //     if (/^on/.test(key)) {
    //         window.addEventListener(key.slice(2), event => {
    //             console.log(event);
    //         });
    //     }
    // });

}, { foo: 'bar'});
