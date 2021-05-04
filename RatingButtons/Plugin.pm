########################################################################################################################
#
# flipflip's RatingButtons plugin
#
# Copyright (c) 2021 Philippe Kehl (flipflip at oinkzwurgl dot org)
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
########################################################################################################################

package Plugins::RatingButtons::Plugin;

use strict;
use warnings;

use base qw(Slim::Plugin::Base);

use Plugins::RatingButtons::Common ':all';
use Plugins::RatingButtons::Settings;
use Slim::Control::Request;
use Slim::Hardware::IR;
use Slim::Utils::Timers;
use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Strings qw(string);
use Slim::Hardware::IR;
use Slim::Music::TitleFormatter;
use Slim::Menu::TrackInfo;
use Slim::Web::Pages;
use Slim::Web::Pages::JS;
use Slim::Web::HTTP;

our $LOG = Slim::Utils::Log->addLogCategory( # Logger
{
    'category'     => 'plugin.ratingbuttons',
    'defaultLevel' => 'ERROR',
    'description'  => 'PLUGIN_RATINGBUTTONS',
});

our $PREFS               = preferences('plugin.ratingbuttons'); # Plugin preferences
our $IRCOMMAND           = undef; # Original IR command
# our $ORIGBUTTONCOMMAND   = undef; # Original buttons command
# our $ORIGJIVEFAVCOMMAND  = undef; # Original Radio (?) favorites command
our $IRSTATE             = {};    # IR code handling state
our $BUTTONS             = {};    # buttons lookup table: { name => { single => 'command', hold => 'command' }, ... }

sub initPlugin
{
    my ($class) = @_;
    $LOG->debug('initPlugin()');

    # Register settings web interface
    if (main::WEBUI)
    {
        Plugins::RatingButtons::Settings->new();
    }

    # Initialise settings (defaults)
    $PREFS->init(
    {
        buttons_en => $Plugins::RatingButtons::Common::PREF_BUTTONS_EN_DEFAULT,
        buttons    => $Plugins::RatingButtons::Common::PREF_BUTTONS_DEFAULT,
    });

    # Subscribe to changes in the buttons preference, and fire it once to update our buttons lookup table
    $PREFS->setChange(\&prefChange, 'buttons');
    prefChange('buttons', $PREFS->get('buttons'));

    # Patch IR handler (in a few seconds, à la KidsPlay plugin) so that we can handle the IR *codes* and buttons ourselves
    Slim::Utils::Timers::setTimer(undef, (Time::HiRes::time() + 3), \&patchIrCommand);

    # An alternative approach might be something like this:
    # Slim::Buttons::Common::setFunction('ratingbuttons', \&handleRatingButtonsCommand);
    # Slim::Control::Request::subscribe( \&patchPlayerButtonMap, [ [ 'client' ] ], [ [ 'new' ] ] );

    # Add title formats
    # For player display: Settings -> Player -> Basic Settings -> Title Format
    # For (default) web interface: Settings -> Interface -> Title Format
    addTitleFmt('RATINGBUTTONS_RATING_NOTES', sub { return titleFmt('rating_notes', @_); });
    addTitleFmt('RATINGBUTTONS_RATING_STARS', sub { return titleFmt('rating_stars', @_); });
    addTitleFmt('RATINGBUTTONS_RATING_WEB',   sub { return titleFmt('rating_web',   @_); });

    # Replace original rating info handler (for player menu and web interface) FIXME: good idea?
    Slim::Menu::TrackInfo->registerInfoProvider( ratingbuttons_rating => ( before => 'moreinfo', func => \&infoRating ) );

    # Inject our Javascript into the main js code (which is included by the main html page)
    if (main::WEBUI)
    {
        Slim::Web::Pages->addPageFunction('js-main-ratingbuttons.js', \&pageFunctionHandler);
        Slim::Web::Pages::JS->addJSFunction('js-main', 'js-main-ratingbuttons.js');
    }

    # Register (JSONRPC) command to set rating of a track
    Slim::Control::Request::addDispatch([ 'ratingbuttons', 'setrating', '_trackid', '_stars' ], [ 0, 0, 1, \&setRating ]);

    $class->SUPER::initPlugin(@_);
}

# sub patchPlayerButtonMap
# {
#     my ($request) = @_; # Slim::Control::Request
#     my $client = $request->client();
#     # $request->getRequestString()); # "client new"
#     # Get current IR map
#     my $irMaps = $client->irmaps(); # { common => { button => '...', button.hold => '...', ..., play => '...', ... }, somemode => { ... }, ... }
#     $LOG->debug(fmt('irmaps=%s', $irMaps));
#     # Patch map, e.g. for the "add" button
#     # - Remove all $irMap->{*}->{add*} (for all @Slim::Hardware::IR::buttonPressStyles)
#     # - Add $irMap->{...}->{add.single} = 'ratingbuttons_funcarg'
#     #       $irMap->{...}->{add.hold}   = 'ratingbuttons_funcarg'
#     #   Where 'funcarg' would be something like 'show', 'rate_5', 'toggle_0_5', ...
#     # - Update map
#     #   $client->irmaps($irMap)
#     # This should patch the IR map to our desired functions independent of what IR/*.map says.
#     # But what if our config changes? Or the client's map changes (user switching .map in webinterface)?
# }
#
# sub handleRatingButtonsCommand
# {
#     my ($client, $button, $funcarg) = @_; # Slim::Player::Client, 'add', 'show')
#     # Do the RatingButtons thing...
# }

# Handle changes (and initial load) of (some) preferences
sub prefChange
{
    my ($prefName, $prefValue) = @_;
    #$LOG->debug(fmt('%s=%s', $prefName, $prefValue));

    # Update buttons lookup table
    if ( ($prefName eq 'buttons') && UNIVERSAL::isa($prefValue, 'ARRAY') )
    {
        $BUTTONS = {};
        for (my $ix = 0; ($ix <= $#{$prefValue}) && ($ix < $Plugins::RatingButtons::Common::MAX_BUTTONS); $ix++)
        {
            # Validate configured button actions, store only valid ones
            my $button = $prefValue->[$ix];
            foreach my $style (qw(single hold))
            {
                if ($button->{$style})
                {
                    my ( $err, @cmdAndArgs ) = validateActionStr($button->{$style});
                    if ($err)
                    {
                        $BUTTONS->{ $button->{name} }->{$style} = [ 'pass' ]; # Ignore
                        $LOG->error("Bad action $button->{name}.$style = $button->{$style}: $err");
                    }
                    else
                    {
                        $BUTTONS->{ $button->{name} }->{$style} = \@cmdAndArgs;
                        $LOG->debug(fmt("Using %-15s %-6s = %s", $button->{name}, $style, join(' / ', @cmdAndArgs)));
                    }
                }
            }
        }
    }
    else
    {
        $LOG->warn('Unhandled pref: ' . $prefName);
    }
}

# Replace IR command handler with our own handler
sub patchIrCommand
{
    # Replace original IR code handler (Slim::Control::Commands::irCommand(), set in Slim::Control::Request::init())
    if (!defined $IRCOMMAND)
    {
        $IRCOMMAND = Slim::Control::Request::addDispatch([ 'ir', '_ircode', '_time' ], [ 1, 0, 0, \&irCommand ]);
        $LOG->debug('Custom irCommand() request handler installed');
    }
    # # Replace original button handler (Slim::Control::Commands::buttonCommand(), set in Slim::Control::Request::init())
    # if (!defined $ORIGBUTTONCOMMAND)
    # {
    #     $ORIGBUTTONCOMMAND = Slim::Control::Request::addDispatch( [ 'button', '_buttoncode', '_time', '_orFunction' ], [ 1, 0, 0, \&buttonCommand ]);
    # }
    # # Replace original favorites button handler (Slim::Control::Jive::jiveFavoritesCommand(), set in Slim::Control::Jive::init())
    # if (!defined $ORIGJIVEFAVCOMMAND)
    # {
    #     $ORIGJIVEFAVCOMMAND = Slim::Control::Request::addDispatch([ 'jivefavorites', '_cmd' ], [ 1, 0, 1, \&jiveFavoritesCommand ]);
    # }
}

# Pass request on to the original irCommand()
sub doOrigIrCommand
{
    my ($request) = @_;
    if ($IRCOMMAND)
    {
        $IRCOMMAND->($request);
    }
    else
    {
        $request->setStatusDone();
    }
}

# # Pass request on to the original buttonCommand()
# sub doOrigButtonCommand
# {
#     my ($request) = @_;
#     if ($ORIGBUTTONCOMMAND)
#     {
#         $ORIGBUTTONCOMMAND->($request);
#     }
#     else
#     {
#         $request->setStatusDone();
#     }
# }

# # Pass request on to the original jiveFavoritesCommand()
# sub doOrigJiveFavoritesCommand
# {
#     my ($request) = @_;
#     if ($ORIGJIVEFAVCOMMAND)
#     {
#         $ORIGJIVEFAVCOMMAND->($request);
#     }
#     else
#     {
#         $request->setStatusDone();
#     }
# }

# sub jiveFavoritesCommand
# {
#     my ($request) = @_;
#     my $cmd = $request->getParam('_cmd');
#     my $key = $request->getParam('key');
#     $LOG->debug(fmt('cmd=%s key=%s', $cmd, $key));
#     doOrigJiveFavoritesCommand($request);
# }

# sub buttonCommand
# {
#     my ($request) = @_;
#     my $buttoncode = $request->getParam('_buttoncode');
#     $LOG->debug(fmt('buttoncode=%s', $buttoncode));
#     doOrigButtonCommand($request);
# }

# Our IR command handler, which handles our buttons and otherwise forwards the request to the original IR command handler
sub irCommand
{
    my ($request) = @_; # Slim::Control::Request

    # Skip if our buttons are disabled
    if (!$PREFS->get('buttons_en'))
    {
        doOrigIrCommand($request);
        return;
    }

    my $client = $request->client();
    my $irCode = $request->getParam('_ircode');
    my $irName = Slim::Hardware::IR::lookupCodeBytes($client, $irCode); # 'add', 'play', ...
    my $irTime = $request->getParam('_time'); # 123.456

    #$LOG->debug(fmt('irCode=%s irName=%s irTime=%.3f', $irCode, $irName, $irTime));

    # Handle Boom buttons
    # - They come in as 'preset_1.down', 'preset_1.up', 'add.down', 'add.up', ...
    # - The first event is 'xxx.down', and a 500ms pause until the next event (either 'xxx.up' or more 'xxx.down' if the button is held)
    my $isBoomButton = 0;
    if ($irName =~ m{^(.+)\.(.+)})
    {
        $isBoomButton = 1;
        $irName = $1;
    }

    # Dispatch to original handler unless it's one of our buttons
    if (!$BUTTONS->{$irName})
    {
        doOrigIrCommand($request);
        return;
    }

    # Handle our buttons. We use a simplified approach (compared to the original Slim::Control::Commands::irCommand()).
    # We only handle .single and .hold presses and we do not consider any repeats. I.e. the user either presses the
    # button only briefly, which is our .single event, or he presses it for a bit longer, which is our .hold event.
    # If the user keeps pressing the button even though the .hold event has been fired, we just ignore that.

    my $clientId = $client->id(); # "xx:xx:xx:xx:xx:xx"

    # IR buttons delta time + some FIXME: this isn't very reliable... :-/
    my $timerDeltaTime = 2 * $Slim::Hardware::IR::IRSINGLETIME;

    # Button down, first IR event
    if (!$IRSTATE->{$clientId}->{$irName})
    {
        $IRSTATE->{$clientId}->{$irName} = { first => $irTime, done => 0 };
        # Add extra time for the first Boom button event (see above)
        if ($isBoomButton)
        {
            $timerDeltaTime += 0.5;
        }
    }
    # Still down
    else
    {
        $IRSTATE->{$clientId}->{$irName}->{last} = $irTime;
    }

    # Start a timer that will fire after button has been released, if user keeps pressing the buttons we repeatedly
    # get here again, kill the timer and restart it
    Slim::Utils::Timers::killTimers($client, \&checkIr);
    Slim::Utils::Timers::setTimer($client, Time::HiRes::time() + $timerDeltaTime, \&checkIr, $irName, $request, $irTime);

    # Button has been held long enough to be a .hold event. Dispatch that event.
    if (!$IRSTATE->{$clientId}->{$irName}->{done} && $IRSTATE->{$clientId}->{$irName}->{last} && 
        (($IRSTATE->{$clientId}->{$irName}->{last} - $IRSTATE->{$clientId}->{$irName}->{first}) > $Slim::Hardware::IR::IRHOLDTIME))
    {
        # Dispatch
        handleButton($irName, 'hold', $request);
        # And do no more events for this button (we don't do repeated .hold)
        $IRSTATE->{$clientId}->{$irName}->{done} = 1;
    }
    # Otherwise the following will fire when the button has been released
    sub checkIr
    {
        my ($client, $irName, $request, $irTime) = @_;
        my $clientId = $client->id();

        # Not yet done, i.e. it wasn't a .hold, and hence must be a .single press
        if (!$IRSTATE->{$clientId}->{$irName}->{done})
        {
            # Dispatch
            handleButton($irName, 'single', $request);
        }
        # Clear info
        delete $IRSTATE->{$clientId};
    }

    # The request will finally terminate in handleButtons()
}

# Execute action
sub handleButton
{
    my ($irName, $style, $request) = @_; # 'add', ... / 'single', 'hold' / Slim::Control::Request

    # ----- What should we do? -----------------------------------------------------------------------------------------

    # Pass on to original handler if we have no action for this button
    my $action = $BUTTONS->{$irName}->{$style};
    if (!$action)
    {
        doOrigIrCommand($request);
        return;
    }

    # Get player mode
    my $client     = $request->client(); # Slim::Player::Client
    my $playerMode = $client->getMode(); # "INPUT.List", "screensaver", "playlist", ...

    # Won't do anyting when off, let the original handler worry about that...
    if ($playerMode =~ m{^(off|block)}i) # "OFF.datetime", ...
    {
        doOrigIrCommand($request);
        return;
    }

    # The button action to handle
    my ($cmd, @args) = @{ $BUTTONS->{$irName}->{$style} };
    $LOG->debug("($playerMode) $irName.$style, action: $cmd @args");

    # ----- Do actions not specific to playing/selected track ----------------------------------------------------------

    # exec() actions can execute without a track, unless they need it
    if ( ($cmd eq 'exec') && ("@args" !~ m{\$trackId}i) )
    {
        $LOG->debug("EXEC EARLY");
        doExec($client, @args);
        $request->setStatusDone();
        return
    }

    # ----- Do actions specific to playing/selected track --------------------------------------------------------------

    # Find track that we want to rate, something like what $Slim::Buttons::Common::functions{favorites} does
    my $track = undef;

    # Now playing list
    if ($playerMode eq 'playlist')
    {
        $track = Slim::Player::Playlist::song($client, Slim::Buttons::Playlist::browseplaylistindex($client));
    }
    # Track currently selected in browse (or other) menu
    elsif (substr($playerMode, 0, 6) eq 'INPUT.')
    {
        my $listRef = $client->modeParam('listRef');
        my $listIx  = $client->modeParam('listIndex');
        if (defined $listRef && defined $listIx)
        {
            my $listEntry = $listRef->[$listIx];
            if (UNIVERSAL::isa($listEntry, 'HASH') && $listEntry->{url})
            {
                $track = Slim::Schema->objectForUrl({ url => $listEntry->{url}, create => 1, readTags => 1 });
            }
        }
    }
    # (else: screensaver) Use currently playing track -- Note: "off" and "block" modes are already handled aboce
    else
    {
        $track = Slim::Player::Playlist::song($client); # Slim::Schema::Track
        # But only if actually playing
        if ( !($client->isPlaying() || $client->isPaused()) )
        {
            $track = undef;
        }
    }
    #$LOG->debug(fmt('modeParam track=%s', $client->modeParam('track')));

    # So maybe we have a usable $track now..
    if ($track)
    {
        # We have some other object
        if (!UNIVERSAL::isa($track, 'Slim::Schema::Track'))
        {
            $track = undef;
        }
        # Won't (can't?) rate remote tracks
        elsif ($track->isRemoteURL())
        {
            $track = undef;
        }
    }

    # Now we really should have a $track that we can rate
    if ($track)
    {
        $LOG->debug('trackid ' . $track->id());
        my $trackTitle  = $track->title();      # "Eiland"
        my $trackArtist = $track->artistName(); # "Phenomden & The Scrucialists"

        # Current rating
        my $trackRating = $track->rating();           # undef, 0..100
        my $trackStars  = rating2stars($trackRating); # 0..5
        my $newStars    = $trackStars;

        my $showRatingDuration = 0;

        # Show rating
        if ($cmd eq 'show')
        {
            $LOG->debug("$trackTitle by $trackArtist, Rating: $trackStars");
            $showRatingDuration = $args[0];
        }
        # Toggle rating
        elsif ($cmd eq 'toggle')
        {
            $newStars = $trackStars == $args[0] ? $args[1] : $args[0];
            $showRatingDuration = 2.0;
        }
        # Set rating
        elsif ($cmd eq 'rate')
        {
            $newStars = $args[0];
            $showRatingDuration = 2.0;
        }
        # Increment rating
        elsif ($cmd eq 'inc')
        {
            $newStars = clipInt($trackStars + $args[0], 0, 5, $trackStars);
            $showRatingDuration = 2.0;
        }
        # Decrement rating
        elsif ($cmd eq 'dec')
        {
            $newStars = clipInt($trackStars - $args[0], 0, 5, $trackStars);
            $showRatingDuration = 2.0;
        }
        # Execute request
        elsif ($cmd eq 'exec')
        {
            $LOG->debug("EXEC WITH TRACK");
            doExec($client, $cmd, @args);
            # Interpolate arguments
            @args = map
            {
                s{\$trackId}{$track->id()}gie;
                $_
            } @args;
            doExec($client, @args);
        }
        # Ignore
        elsif ($cmd eq 'pass')
        {
            # ...
        }
        # Nope (shouldn't happen as we have only stored verified actions in $BUTTONS)
        else
        {
            $LOG->error("Bad action: $cmd @args");
        }

        # Update rating
        if ($newStars != $trackStars)
        {
            $LOG->debug("$trackTitle by $trackArtist, New rating: $newStars");
            $track->rating( stars2rating($newStars) );
            $client->showBriefly(
                { line => [ sprintf(string('PLUGIN_RATINGBUTTONS_SONGBYARTIST'), $trackTitle, $trackArtist),
                            sprintf(string('PLUGIN_RATINGBUTTONS_NEWRATINGIS'), (stars2text($newStars) || string('PLUGIN_RATINGBUTTONS_NORATING'))) ] },
                { duration => $showRatingDuration, brightness => 'powerOn', });
            # Clear display cache, e.g. for our custom formats
            Slim::Music::Info::clearFormatDisplayCache();
        }
        # Or perhaps just show the current rating
        elsif ($showRatingDuration)
        {
            $client->showBriefly(
                { line => [ sprintf(string('PLUGIN_RATINGBUTTONS_SONGBYARTIST'), $trackTitle, $trackArtist),
                            sprintf(string('PLUGIN_RATINGBUTTONS_RATINGIS'), (stars2text($trackStars) || string('PLUGIN_RATINGBUTTONS_NORATING'))) ] },
                { duration => $showRatingDuration, brightness => 'powerOn' });
        }
    }
    # No track...
    else
    {
        $LOG->debug('No track to rate');
        $client->showBriefly(
            { line => [ ':-(', string('PLUGIN_RATINGBUTTONS_NOTHING') ] },
            { duration => 1.0, brightness => 'powerOn' });
        return;
    }

    $request->setStatusDone();
}

sub doExec
{
    my ($client, $player, $message, @command) = @_;

    my @clients = ();
    if ($player eq 'this')
    {
        push(@clients, $client);
    }
    elsif ($player =~ m{^(others?|all)$}i)
    {
        push(@clients, Slim::Player::Client::clients());
        if ($player =~ m{^others?$}i)
        {
            @clients = grep { $_->id() ne $client->id() } @clients;
        }
    }
    else
    {
        my $c = Slim::Player::Client::getClient($player);
        if ($c)
        {
            push(@clients, $c);
        }
    }
    
    if ($#clients < 0)
    {
        $LOG->error("No client(s) for exec($player, ...) action!");
        return;
    }

    foreach my $c (@clients)
    {
        $LOG->debug("exec(@command) for client " . $c->id() . ' (' . $c->name() . ')');
        Slim::Control::Request::executeRequest($c, \@command); # or $client->execute()
    }

    if ($message)
    {
        $client->showBriefly(
            { line => [ string('PLUGIN_RATINGBUTTONS'), $message ] },
            { duration => 2.0, brightness => 'powerOn' });
    }

    return;
}

sub addTitleFmt
{
    my ($name, $formatter) = @_;

    # Register the format
    Slim::Music::TitleFormatter::addFormat($name, $formatter);

    # Add it to the list of configured formats
    # FIXME: In case the user has deleted this format, this will re-add the format on restart
    my $titleFormats = preferences('server')->get('titleFormat');
    if (!scalar grep { $_ eq $name } @{$titleFormats})
    {
        push(@{$titleFormats}, $name);
        #preferences('server')->set('titleFormat', $titleFormats);
    }
}

sub titleFmt
{
    my ($which, $track) = @_;

    if (!UNIVERSAL::isa($track, 'Slim::Schema::Track'))
    {
        return ' ';
    }

    # Return note symbols or a space if no rating
    if ($which eq 'rating_notes')
    {
        my $trackRating = $track->rating();           # undef, 0..100
        my $trackStars  = rating2stars($trackRating); # 0..5
        return stars2text($trackStars, '') || ' ';
    }
    # Return stars or a space if no rating
    elsif ($which eq 'rating_stars')
    {
        my $trackRating = $track->rating();           # undef, 0..100
        my $trackStars  = rating2stars($trackRating); # 0..5
        return stars2text($trackStars, '', '*') || ' ';
    }
    # Return specially formatted text that we can perse in js-main-ratingbuttons.js
    elsif ($which eq 'rating_web')
    {
        if (UNIVERSAL::isa($track, 'Slim::Schema::Track') && !$track->isRemoteURL())
        {
            my $trackRating = $track->rating();           # undef, 0..100
            my $trackStars  = rating2stars($trackRating); # 0..5
            return 'RATINGBUTTONS_RATING_WEB=/' . $trackStars  . ',' . $track->id() . '/';
        }
        else
        {
            return '';
        }
    }
    else
    {
        return '?';
    }
}

sub infoRating
{
    my ( $client, $url, $track ) = @_; # Slim::Player::Client, string, Slim::Schema::Track

    my $strNothing = string('PLUGIN_RATINGBUTTONS_NOTHING');
    my $item =
    {
        type    => 'text',
        label   => 'RATING',
        name    => $strNothing,
        html    => { name => $strNothing, stars => -1 },
        web     => { type => 'htmltemplate', value => 'plugins/RatingButtons/inforating.html' },
    };

    if (UNIVERSAL::isa($track, 'Slim::Schema::Track'))
    {
        my $trackRating = $track->rating();           # undef, 0..100
        my $trackStars  = rating2stars($trackRating); # 0..5
        my $strNorating = string('PLUGIN_RATINGBUTTONS_NORATING');
        $item->{name} = stars2text($trackStars) || $strNorating;
        $item->{html}->{name} = titleFmt('rating_web', $track);
        $item->{html}->{stars} = $trackStars;

        # Add sub-menu to update the rating
        delete $item->{type};
        my $strSetrating = string('PLUGIN_RATINGBUTTONS_SETRATING');
        my @items = ();
        for (my $stars = 0; $stars <= 5; $stars++)
        {
            push(@items,
            {
                name => sprintf($strSetrating, stars2text($stars) || $strNorating),
                url => \&infoRatingSet, passthrough => [ $track, $stars ],
            });
        }
        $item->{items} = \@items;
    }

    return $item;
}

sub infoRatingSet
{
    my ($client, $callback, $params, $track, $stars) = @_;

    $track->rating( stars2rating($stars) );
    Slim::Music::Info::clearFormatDisplayCache();
    $callback->([
    {
        type => 'text',
        name => sprintf(string('PLUGIN_RATINGBUTTONS_NEWRATINGIS'), (stars2text($stars) || string('PLUGIN_RATINGBUTTONS_NORATING'))),
        # Show message briefly and then jump back to track listing
        # FIXME: how can we make the parent-parent menu text update with the new rating?!
        showBriefly => 1, popback => 3,
        favorites => 0, refresh => 1
    }]);
}

sub pageFunctionHandler
{
    my ($client, $params) = @_; # Slim::Player::Client, HASH
    $params->{ratingbuttons} =
    {
        clientId => $client->id(),
    };
    return Slim::Web::HTTP::filltemplatefile('js-main-ratingbuttons.js', $params);
}

sub setRating
{
    my ($request) = @_; # Slim::Control::Request
    # 'ratingbuttons', 'setrating', '_trackid', '_stars'

    my $trackId = $request->getParam('_trackid');
    my $stars   = $request->getParam('_stars');
    my $track   = Slim::Schema->resultset('Track')->find($trackId);
    if (defined $stars && UNIVERSAL::isa($track, 'Slim::Schema::Track'))
    {
        $LOG->debug(fmt('trackId=%s stars=%s', $trackId, $stars));
        $track->rating( stars2rating($stars) );
        Slim::Music::Info::clearFormatDisplayCache();
    }

    $request->setStatusDone();
}

1;
########################################################################################################################
