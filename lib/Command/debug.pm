package Command::debug;

use v5.10;
use strict;
use warnings;

use Exporter qw(import);
our @EXPORT_OK = qw(cmd_debug);

use Bot::Framework;
use Discord::Players;
use Discord::Send;
use Data::Dumper;
use Mojo::Discord;

###########################################################################################
# Command q
my $command = "debug";
my $access = 0; # Public
my $description = "Display debugrmation about the bot, including framework, creator, and source code";
my $pattern = '^stats\.debug\s[a-z]+$';
my $function = \&cmd_debug;
my $usage = <<EOF;
Usage:
 `debug <on | off>`
EOF
###########################################################################################

sub new
{
	my ($class, %params) = @_;
	my $self = {};
	bless $self, $class;
	 
	# Setting up this command module requires the Discord connection 
	$self->{'bot'} = $params{'bot'};
	$self->{'discord'} = $self->{'bot'}->discord;
	$self->{'pattern'} = $pattern;
	$self->{'command'} = $command;

	# Register our command with the bot
	$self->{'bot'}->add_command(
		'command'	=> $command,
		'access'	=> $access,
		'description'	=> $description,
		'usage'		=> $usage,
		'pattern'	=> $pattern,
		'function'	=> $function,
		'object'	=> $self,
	);

	$self->{send} = Discord::Send->new('bot' => $self->{bot});
	if (!defined($self->{bot}->{players})) {
		$self->{bot}->{players} = Discord::Players->new('bot' => $self->{bot});
	}

	return $self;
}

sub cmd_debug
{
	my ($self, $channel, $author, $msg) = @_;

	my $discord = $self->{'discord'};
	my $bot = $self->{'bot'};

	my $replyto = '<@' . $author->{id} . '>';

	my $player = $bot->{players}->get_player($author);
	my $id = $player->get_id;

	my $debug = "";
	my $dask = 0;

	my $deb = $bot->{debug};
	if ($msg =~ /debug on$/) {
		$dask = 1;
	} elsif ($msg =~ /debug off$/) {
		$dask = 0;
	} else {
		$debug = $usage;
	}

	if ($dask == $deb) {
		$debug .= "stats.debug = ${deb}, no change\n";
	} else {
		$debug .= "stats.debug: ${deb} -> ${dask}\n";
		$bot->{debug} = $dask;
	}
	
	# We can use some special formatting with the webhook.
	if ( my $hook = $bot->has_webhook($channel) )
	{
		$discord->send_webhook($channel, $hook, $debug);
	} else {
		$discord->send_message($channel, $debug);
	}
}

1;
