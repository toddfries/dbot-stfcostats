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

	my $q = "select id from players where did='".$author->{id}."'";

	my $id = $bot->{'db'}->do_oneret_query($q);
	if (defined($id) && $id > -1) {
		$info = "Your id in my db is ${id}, did ".$author->{id};
	} else {
		$q = "INSERT INTO players ( did ) values ( '".$author->{id}."')";
		my $oid = $bot->{'db'}->do_oid_insert($q, 'o::cmd_info');
		$q = "SELECT id FROM players where oid = ${oid}";
		$id = $bot->{db}->do_oneret_query($q);
		$info = "Added your id in my db, it is ${id}, did ".$author->{id};
	}
	
	# We can use some special formatting with the webhook.
	if ( my $hook = $bot->has_webhook($channel) )
	{
		$discord->send_webhook($channel, $hook, $info);
	} else {
		$discord->send_message($channel, $info);
	}
}

1;
