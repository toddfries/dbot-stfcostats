package Command::new;

use v5.10;
use strict;
use warnings;

use Exporter qw(import);
our @EXPORT_OK = qw(cmd_new);

use Bot::Framework;
use Data::Dumper;
use Discord::Players;
use Discord::Send;
use Mojo::Discord;

###########################################################################################
# Command q
my $command = "new";
my $access = 0; # Public
my $description = "Display information about the bot, including framework, creator, and source code";
my $pattern = '^new\s+([a-z]+)\s+([a-z][a-z_]+)\s(.*)$';
my $function = \&cmd_new;
my $usage = <<EOF;
Usage:
 `new <type> <shortname> <longname>`

Example:
 `new buff adv_train Advanced Training`
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

sub cmd_new
{
	my ($self, $channel, $author, $msg) = @_;

	my $discord = $self->{'discord'};
	my $bot = $self->{'bot'};

	my $replyto = '<@' . $author->{id} . '>';
	my $user = $author->{username}."#".$author->{discriminator};
	#print Dumper($author);

	my $info;

	my $player = $bot->{players}->get_player($author);
	my $id = $player->get_id;

	$info = "";

	my @bits;
	foreach my $m (split(/^/,$msg)) {
	@bits = split(/\s+/,$m,4);
	if ($bits[0] =~ /^new$/i) {
		if ($#bits == 3) {
			$info .= $self->newtype($id, $bits[1], $bits[2], $bits[3]);
		} else {
			$info .= "Bits count = ".$#bits."\n";
			$info .= $usage;
		}
	} else {
		$info .= $usage;
	}
	}
	

	$self->{send}->send($channel, $info);
}


sub newtype {
	my ($self, $id, $type, $short, $long) = @_;
	my $bot = $self->{bot};
	my $db  = $bot->{db};

	my $q = "select id from buff_name where buff_name.short_name = ";
	$q .= $db->quote($short);
	my $bid = $db->do_oneret_query($q);
	if ($bid > -1) {
		return "new <type: ${type}> <short: ${short}> <long: ${long}> .. failed!";
	}

	$q = "insert into buff_name (type_name, short_name, long_name) values (";
	$q .= $db->quote($type);
	$q .= ",".$db->quote($short);
	$q .= ",".$db->quote($long);
	$q .= ")";

	my $oid = $db->do_oid_insert($q, '::newtype');

	$q = "select id from buff_name where oid = ${oid}";
	my $newid = $db->do_oneret_query($q);
	return "new ${type} ${short} ${long} = ${newid}";
}

1;
