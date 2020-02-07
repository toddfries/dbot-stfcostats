package Command::i;

use v5.10;
use strict;
use warnings;

use Exporter qw(import);
our @EXPORT_OK = qw(cmd_info);

use Mojo::Discord;
use Bot::Framework;
use Data::Dumper;

###########################################################################################
# Command i
my $command = "i";
my $access = 0; # Public
my $description = "Display information about the bot, including framework, creator, and source code";
my $pattern = '^i\s';
my $function = \&cmd_info;
my $usage = <<EOF;
Usage: `o <shortname> <rank> <level> <attack> <defense> <health>`
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
	my ($self, $channel, $author, $msg) = @_;

	my $discord = $self->{'discord'};
	my $bot = $self->{'bot'};

	my $replyto = '<@' . $author->{id} . '>';

	my $info="";

	my $q = "select id from players where did='".$author->{id}."'";

	my $id = $bot->{'db'}->do_oneret_query($q);
	if (defined($id) && $id > -1) {
		#$info = "Your id in my db is ${id}, did ".$author->{id};
	} else {
		$q = "INSERT INTO players ( did ) values ( '".$author->{id}."')";
		my $oid = $bot->{'db'}->do_oid_insert($q, 'i::cmd_info');
		$q = "SELECT id FROM players where oid = ${oid}";
		$id = $bot->{db}->do_oneret_query($q);
		#$info = "Added your id in my db, it is ${id}, did ".$author->{id};
	}

	#print Dumper($msg);
	foreach my $m (split(/^/,$msg)) {

	my (@bits) = split(/\s+/,$m);
	if ($bits[0] eq "i") {
		if ($#bits == 6) {
			#$info .= sprintf("\nStats parsed as: shortname='%s', rank=%d, level=%d, attack=%d, defense=%d, health=%d\n", $bits[1], $bits[2], $bits[3], $bits[4], $bits[5], $bits[6]);
			$info .= $self->update_stats($id, @bits);
		} else {
			$info .= $usage;
		}
	} else {
		$info .= $usage;
	}
	}
	
	# We can use some special formatting with the webhook.
	if ( my $hook = $bot->has_webhook($channel) )
	{
		$discord->send_webhook($channel, $hook, $info);
	} else {
		$discord->send_message($channel, $info);
	}
}

# XXX note where changes occur, and mention them
sub update_stats {
	my ($self, $player_id, $cmd, $shortname, $rank, $level, $attack, $defense, $health) = @_;
	my $bot = $self->{bot};

	my $short_quote = $bot->{'db'}->quote(lc($shortname));

	my $q = "select id from officers where short = ${short_quote}";
	my $officer_id = $bot->{'db'}->do_oneret_query($q);
	if (defined($officer_id) && $officer_id == -1) {
		$q = "INSERT INTO officers ( short ) values ( ${short_quote} )";
		my $oid = $bot->{'db'}->do_oid_insert($q, 'i::update_stats');
		$q = "SELECT id FROM officers where oid = ${oid}";
		$officer_id = $bot->{db}->do_oneret_query($q);
	}

	$q = "select id from ostats where player_id = ${player_id} and officer_id = ${officer_id}";
	my $stat_id = $bot->{db}->do_oneret_query($q);
	my $qret;
	if (defined($stat_id) && $stat_id == -1) {
		$q = "INSERT INTO ostats (player_id, officer_id, rank, level, attack, defense, health) ";
		$q .= "VALUES ";
		$q .= sprintf("(%d, %d, %d, %d, %d, %d, %d)", $player_id, $officer_id, $rank, $level, $attack,
		    $defense, $health);
		$qret = $bot->{db}->doquery($q);
	} else {
		$q  = "UPDATE ostats set ";
		$q .= sprintf("rank=%d, level=%d, attack=%d, defense=%d, health=%d ",
			$rank, $level, $attack, $defense, $health);
		$q .= " where player_id = ${player_id} and officer_id = ${officer_id}";
		$qret = $bot->{db}->doquery($q);
	}
	return "Saved ${shortname} bits!";
}

1;
