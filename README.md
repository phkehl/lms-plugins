# flipflip's LMS plugins

For [Logitech Media Server](https://github.com/Logitech/slimserver)

Repo URL: <https://raw.githubusercontent.com/phkehl/lms-plugins/main/repo.xml>

## Rating Buttons

Use remote buttons to rate songs.

Inspired by the [RatingsLight](https://github.com/AF-1/lms-ratingslight) and
[KidsPlay](https://tuxreborn.netlify.app/slim/kidsplay) plugins.

For each button a single (short) button press and and a button hold action can be defined. Each button defined here
loses its original functionality in all modes for those actions that are defined. Leave the field empty to keep the
button's original single press or button hold functionality.

The actions are in the form of `action` or `action(argument, argument, ...)`, where `action` is one of the actions
described below. Some actions take one or more `argument`s. Some arguments are optional (have a default value). The
actions apply to the currently playing track or, if in playlist or browse mode, the currently selected track. Rating
values are in "stars". Possible values are 1, 2, 3, 4 or 5. A value of 0 means "no rating" or "remove rating".

The available actions are:

- `show` or  `show(duration)`: Shows the rating on the display. The optional duration is a value in seconds from 0.1 to
  10.0. The default duration is 2 (seconds).
- `toggle(first, second)`: Toggles the rating between the first and second value and shows the updated rating briefly on
  the display.
- `rate(value)`: Sets the rating to the value and shows the updated rating briefly on the display.
- `inc(value)` or `dec(value)`: Increments or decrements the rating by a value (default: 1) and shows the updated rating
  briefly on the display.
- `pass`: Does nothing.

See [Plugin.pm](./RatingButtons/Plugin.pm) for the implementation.

![screenshot](RatingButtons-screenshot.png)

![demo](RatingButtons-demo.gif)

**Changelog:**

- v0.2 -- 2021-02-06
  - Handle Boom hardware buttons (e.g. 'preset_1', 'add'). This is largely untested.
- v0.1 -- 2021-02-05
  - Initial version

