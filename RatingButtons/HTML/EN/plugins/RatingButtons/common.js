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

const ratingTitles =
[
    'Set rating to no stars',
    'Set rating to one star',
    'Set rating to two stars',
    'Set rating to three stars',
    'Set rating to four stars',
    'Set rating to five stars',
];

const ratingExtractRe = '(.*)(?:RATINGBUTTONS_RATING_WEB=/([012345]),([0-9]+)/)(.*)';

// Render the rating thingy
function renderRating(container, stars)
{
    // Generate HTML markup for the rating
    let html = '';
    if (stars > 0)
    {
        html += '<span class="ratingbuttons-rating-none" '+
            'title="' + ratingTitles[0] + '" data-stars="0">&#215;</span>';
    }
    for (let s = 5; s > 0; s--)
    {
        html += '<span class="ratingbuttons-rating-star ' + 
            'ratingbuttons-rating-' + (s <= stars ? 'black' : 'grey') + '" ' +
            'data-stars="' + s + '" title="' + ratingTitles[s] + '">&#9733;</span>';
    }
    container.innerHTML = html;
}

function updateRating(div, e)
{
    // Retrieve the track ID (from the div) and the rating associated to the actually clicked element
    // (first star = 1, second star = 2, ..., the x = 0)
    let id = div.dataset.trackId;
    let st = e.target.dataset.stars;
    //console.log('track ' + id + ' stars ' + st);
    
    // Send request to server to set this track's rating as clicked
    ajaxRequest('/jsonrpc.js', { id: 1, method: 'slim.request',
        params: [ '', [ 'ratingbuttons', 'setrating', id, st ], ] });

        // Update the rating thingy
    renderRating(div, st);
};

// Add our CSS FIXME: how to include our CSS in index.html?
let style = document.createElement('style');
style.setAttribute('type', 'text/css');
style.innerHTML = '\
    .ratingbuttons-rating-container { display: inline-block; unicode-bidi: bidi-override; direction: rtl; /*line-height: 1em;*/ }\
    .ratingbuttons-rating-grey, .ratingbuttons-rating-none { display: none; }\
    .draggableSong:hover .ratingbuttons-rating-grey, .draggableSong:hover .ratingbuttons-rating-none,\
    .mouseOver:hover .ratingbuttons-rating-grey, .mouseOver:hover .ratingbuttons-rating-none { display: unset; }\
    .ratingbuttons-rating-black { color: #000; }\
    .ratingbuttons-rating-none  { color: #ddd; }\
    .ratingbuttons-rating-grey  { color: #ddd; }\
    /*.ratingbuttons-rating-star, .ratingbuttons-rating-none { font-size: 1.2em; }*/\
    .ratingbuttons-rating-none:hover { color: #f00; }\
    .ratingbuttons-rating-star:hover { color: #f00; }\
    .ratingbuttons-rating-star:hover ~ .ratingbuttons-rating-star { color: #f00; }\
    .ratingbuttons-rating-none:hover ~ .ratingbuttons-rating-star { color: #ddd; }\
    ';
document.getElementsByTagName('head')[0].appendChild(style);
