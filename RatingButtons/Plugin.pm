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

our $LOG = Slim::Utils::Log->addLogCategory( # Logger
{
    'category'     => 'plugin.ratingbuttons',
    'defaultLevel' => 'ERROR',
    'description'  => 'PLUGIN_RATINGBUTTONS',
});

our $PREFS      = preferences('plugin.ratingbuttons'); # Plugin preferences
our $IRCOMMAND  = undef; # Original IR command (Slim::Control::Commands::irCommand())
our $IRSTATE    = {};    # IR code handling state
our $BUTTONS    = {};    # buttons lookup table: { name => { single => 'command', hold => 'command' }, ... }

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
        buttons_en   => $Plugins::RatingButtons::Common::PREF_BUTTONS_EN_DEFAULT,
        buttons      => $Plugins::RatingButtons::Common::PREF_BUTTONS_DEFAULT,
    });

    # Subscribe to changes in the buttons preference, and fire it once to update our buttons lookup table
    $PREFS->setChange(\&prefChange, 'buttons');
    prefChange('buttons', $PREFS->get('buttons'));

    # Patch IR handler (in a few seconds, à la KidsPlay plugin) so that we can handle the IR *codes* ourselves
    Slim::Utils::Timers::setTimer(undef, (Time::HiRes::time() + 3), \&patchIrCommand);

    # An alternative approach might be something like this:
    # Slim::Buttons::Common::setFunction('ratingbuttons', \&handleRatingButtonsCommand);
    # Slim::Control::Request::subscribe( \&patchPlayerButtonMap, [ [ 'client' ] ], [ [ 'new' ] ] );

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
                        $LOG->debug(fmt("Using %10s.%-6s = %s", $button->{name}, $style, "@cmdAndArgs"));
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
    if (!defined $IRCOMMAND)
    {
        # Replace original IR handler (Slim::Control::Commands::irCommand, set in Slim::Control::Request)
        $IRCOMMAND = Slim::Control::Request::addDispatch([ 'ir', '_ircode', '_time' ], [ 1, 0, 0, \&irCommand ]);
        $LOG->debug('Custom irCommand() request handler installed');
    }
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

    my $irTime   = $request->getParam('_time'); # 123.456
    my $clientId = $client->id(); # "xx:xx:xx:xx:xx:xx"

    # Button down, first IR event
    if (!$IRSTATE->{$clientId}->{$irName})
    {
        $IRSTATE->{$clientId}->{$irName} = { first => $irTime, done => 0 };
    }
    # Still down
    else
    {
        $IRSTATE->{$clientId}->{$irName}->{last} = $irTime;
    }

    # Start a timer that will fire after button has been released, if user keeps pressing the buttons we repeatedly
    # get here again, kill the timer and restart it
    Slim::Utils::Timers::killTimers($client, \&checkIr);
    Slim::Utils::Timers::setTimer($client, Time::HiRes::time() + $Slim::Hardware::IR::IRSINGLETIME, \&checkIr, $irName, $request);

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
        my ($client, $irName, $request) = @_;
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

sub handleButton
{
    my ($irName, $style, $request) = @_; # 'add', ... / , 'single', 'hold' / Slim::Control::Request

    my $action = $BUTTONS->{$irName}->{$style};
    if (!$action)
    {
        doOrigIrCommand($request);
        return;
    }

    # The button action to handle
    my ($cmd, @args) = @{ $BUTTONS->{$irName}->{$style} };

    # Find track that we want to rate, something like $Slim::Buttons::Common::functions{favorites}
    my $track = undef;
    my $client     = $request->client(); # Slim::Player::Client
    my $playerMode = $client->getMode(); # "INPUT.List", "screensaver", "playlist"

    $LOG->debug("($playerMode) $irName.$style: cmd=$cmd args=@args");

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
    # Won't do anyting when off
    elsif ($playerMode =~ m{^(off|block)}i) # "OFF.datetime", ...
    {
        # ...
    }
    # (else: screensaver) Use currently playing track
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

1;
########################################################################################################################
