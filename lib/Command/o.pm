package Command::o;

use v5.10;
use strict;
use warnings;

use Exporter qw(import);
our @EXPORT_OK = qw(cmd_info);

use Mojo::Discord;
use Bot::Framework;
use Data::Dumper;

###########################################################################################
# Command o
my $command = "o";
my $access = 0; # Public
my $description = "Display information about the bot, including framework, creator, and source code";
my $pattern = '^o\s(.*)$';
my $function = \&cmd_info;
my $usage = <<EOF;
Usage: `o <_add_|_list_|_update_>`
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
	
	return $self;
}

sub cmd_info
{
	my ($self, $channel, $author) = @_;

	my $discord = $self->{'discord'};
	my $bot = $self->{'bot'};

	my $replyto = '<@' . $author->{id} . '>';

	my $info;

	my $q = "select id from players where did=".$author->{id}.";";

	$info = "Your Assignment, $replyto, is to scan sector one for ";
	$info .= " lvl27 [ĐÇ] ÅňğëłŐfĐ3åťh (aka HollowGrahms) base.\n";
	$info .= "Sector one: Benzi[4], Dalfa[2], Zanti[1], Tohvus[1], Bo-Jeems[1], Folin[2], Corla[1], Barra[1], Soeller[1]\n";
	
	# We can use some special formatting with the webhook.
	if ( my $hook = $bot->has_webhook($channel) )
	{
		$discord->send_webhook($channel, $hook, $info);
	} else {
		$discord->send_message($channel, $info);
	}
}

1;
