package Bot::C::Core;

=head1 NAME

Bot::C::Core - A singleton that implements the core bot controller.

=head1 SYNOPSIS

    use Bot::C::Core;

    # Enter the application's main loop.
    Bot::C::Core->instance()->run();

=cut

use common::sense;

use base 'Class::Singleton';

use Carp;
use LWP::Simple;
use POE;
use POE::Component::IRC;
use Time::HiRes qw(time);

use Bot::M::Config;
use Bot::V::IRC;
use Bot::V::Log;

sub _ev_tick
{   
    my ($self) = @_[OBJECT];

    my $target = "Sequell";
    my $msg = "!lg teddybear won t turns<=246813579 s=char";

    Bot::V::Log->instance()->log("MSG_OUT($target) $msg");
    Bot::V::IRC->instance()->privmsg($target, $msg);

    $_[HEAP]->{next_alarm_time} = int(time() + 300 + rand(120));
    $_[KERNEL]->alarm(tick => $_[HEAP]->{next_alarm_time});
    Bot::V::Log->instance()->log
    (
        "Set next alarm [$_[HEAP]->{next_alarm_time}]"
    );
}

# The bot is starting up.
sub _ev_bot_start
{
    my ($self) = @_[OBJECT];

    $_[HEAP]->{next_alarm_time} = int(time() + 30 + rand(45));
    Bot::V::Log->instance()->log
    (
        "Set next alarm [$_[HEAP]->{next_alarm_time}]"
    );
    $_[KERNEL]->alarm(tick => $_[HEAP]->{next_alarm_time});

    Bot::V::IRC->instance()->start_session();
}

# The bot has successfully connected to a server.  Join a channel.
sub _ev_on_connect
{
    my ($self) = @_[OBJECT];

    my $config = Bot::M::Config->instance();

    my $password = $config->get_key('irc_nickserv_password');
    Bot::V::Log->instance()->log('Identifying to NickServ');
    Bot::V::IRC->instance()->privmsg('NickServ', "identify $password");

    for my $channel (@{$config->get_key('irc_channels')})
    {
        Bot::V::Log->instance()->log("Joining channel [$channel]");
        Bot::V::IRC->instance()->join($channel);
    }
}

# The bot has received a public message.  Parse it for commands and
# respond to interesting things.
sub _ev_on_public
{
    my ($self) = @_[OBJECT];

    my ($kernel, $who, $where, $msg) = @_[KERNEL, ARG0, ARG1, ARG2];
    my $nick    = (split /!/, $who)[0];
    my $channel = $where->[0];

    Bot::V::Log->instance()->log("MSG($channel) <$nick> $msg");

    my $config = Bot::M::Config->instance();
    my $nick = $config->get_key('irc_nick');

    my $proxies_ref = Bot::M::Config->instance()->get_key('proxies');
    for my $proxy_ref (@$proxies_ref)
    {
        my $prefix = $proxy_ref->{prefix};
        if (length($msg) >= length($prefix) &&
            substr($msg, 0, length($prefix)) eq $prefix)
        {
            my $target = $proxy_ref->{nick};
	    # special hack for henzell ! commands
	    if ($target eq "Sequell" and
		# Not all of these will work in PM anyways, and there
		# is a little overlap with Sequell for unimportant
		# commands
		$msg =~ /!(aplayers|apt|cdefine|cmdinfo|coffee|copysave|dump|echo|eplayers|ftw|function|help|idle|learn|macro|messages|nick|players|rc|rng|screensize|seen|send|skill|source|tell|time|vault|whereis|wtf)/) {
		$target = "Henzell";
	    }
            Bot::V::Log->instance()->log("MSG_OUT($target) $msg");
            Bot::V::IRC->instance()->privmsg($target, $msg);
        }
    }
}

sub current_combos
{
    my $clanpage = "http://seleniac.org/crawl/tourney/12a/clans/ragdoll.html";
    my $clandata = get($clanpage);
    if (defined($clandata)) {
	my ($gamedata) = ($clandata =~ m|Ongoing Games</h3>\s*<div>\s*(.*?)\s*</div>|m);
	my @games = split /<br \/>/, $gamedata;
	my @combos = ();
	foreach my $game (@games) {
	    if (my ($combo) = ($game =~ /\(L\d+ (....)/)) {
		push @combos, $combo;
	    }
	}
	@combos = sort @combos;
	return "@combos";
    } else {
	return "unknown"
    }
}

sub compute_topic
{
    my ($msg) = @_;

    my %races = map { $_ => 1 } qw(Ce DD DE Dg Dr Ds Fe Gh Ha HE HO Hu Ko Mf Mi Mu Na Og Op SE Sp Te Tr Vp);
    my %classes = map { $_ => 1 } qw(AE AK AM Ar As Be Cj CK DK EE En FE Fi Gl He Hu IE Mo Ne Pr Sk St Su Tm VM Wn Wr Wz);

    my ($combos) = ($msg =~ /:(.*)$/);
    foreach my $word (split / /, $combos) {
	my ($race, $class) = ($word =~ /(..)(..),?/) or next;
	delete $races{$race};
	delete $classes{$class};
    }

    return "RACES: " . (join ' ', sort { lc $a cmp lc $b } keys %races)
	. " | CLASSES: " . (join ' ', sort { lc $a cmp lc $b } keys %classes)
	. " | Ongoing games: " . current_combos();
}

sub _ev_on_msg
{
    my ($self) = @_[OBJECT];

    my ($kernel, $who, $where, $msg) = @_[KERNEL, ARG0, ARG1, ARG2];
    my $nick    = (split /!/, $who)[0];

    Bot::V::Log->instance()->log("MSG_IN($nick) $msg");

    if ($msg =~ /246813579/) {
	my $topic = compute_topic($msg);
	Bot::V::IRC->instance()->topic("##crawl-rant", $topic);
	return;
    }

    my $proxies_ref = Bot::M::Config->instance()->get_key('proxies');
    for my $proxy_ref (@$proxies_ref)
    {
        if (lc($nick) eq lc($proxy_ref->{nick}))
        {
            my $channel = $proxy_ref->{target_channel};
            Bot::V::IRC->instance()->privmsg($channel, "$msg");
        }
    }
}

=head1 METHODS

=cut

=head2 run()

Configures the IRC session and begins the POE kernel loop.

=cut
sub run
{
    my ($self) = @_;

    my $config = Bot::M::Config->instance();

    my $irc = POE::Component::IRC->spawn();
    Bot::V::IRC->instance()->configure($irc);

    # Set up events to handle.
    POE::Session->create
    (
        object_states =>
        [
            $self =>
            {
                _start     => '_ev_bot_start',
                irc_001    => '_ev_on_connect',
                irc_public => '_ev_on_public',
                irc_msg    => '_ev_on_msg',
                tick       => '_ev_tick',
            },
        ],
    );

    # XXX move this
    my $nick = $config->get_key('irc_nick');
    Bot::V::Log->instance()->log("Nick is $nick");

    # Run the bot until it is done.
    $poe_kernel->run();
    return 0;
}

1;

=head1 AUTHOR

Colin Wetherbee <cww@denterprises.org>

=head1 COPYRIGHT

Copyright (c) 2011 Colin Wetherbee

=head1 LICENSE

See the COPYING file included with this distribution.

=cut
