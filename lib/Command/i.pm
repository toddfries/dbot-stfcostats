package Command::i;

use v5.10;
use strict;
use warnings;

use Exporter qw(import);
our @EXPORT_OK = qw(cmd_i);

use Bot::Framework;
use Discord::Players;
use Discord::Send;
use Data::Dumper;
use Mojo::Discord;

###########################################################################################
# Command i
my $command = "i";
my $access = 0; # Public
my $description = "Display information about the bot, including framework, creator, and source code";
my $pattern = '^i\s[a-z][a-z0-9_\']+\s[0-9]+\s[0-9]+\s[0-9]+\s[0-9]+\s[0-9]+';
my $function = \&cmd_i;
my $usage = <<EOF;
Usage: `i <shortname> <rank> <level> <attack> <defense> <health>`
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

sub cmd_i
{
	my ($self, $channel, $author, $msg) = @_;

	my $discord = $self->{'discord'};
	my $bot = $self->{'bot'};

	my $replyto = '<@' . $author->{id} . '>';

	my $info="";

	my $player = $bot->{players}->get_player($author);
	my $id = $player->get_id;


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

	$q = "select id,rank,level,attack,defense,health from ostats where player_id = ${player_id} and officer_id = ${officer_id}";
	my $sth = $bot->{db}->doquery($q);
	my $rv = $sth->rows;
	my $stat_id;
	if ($rv < 1) {
		$stat_id = -1;
	}
	my $qret;
	if (defined($stat_id) && $stat_id == -1) {
		$q = "INSERT INTO ostats (player_id, officer_id, rank, level, attack, defense, health) ";
		$q .= "VALUES ";
		$q .= sprintf("(%d, %d, %d, %d, %d, %d, %d)", $player_id, $officer_id, $rank, $level, $attack,
		    $defense, $health);
		$qret = $bot->{db}->doquery($q);
		return "Saved ${shortname} bits!";
	}
	my ($orank, $olevel, $oattack, $odefense, $ohealth);
	($stat_id, $orank, $olevel, $oattack, $odefense, $ohealth) = $sth->fetchrow_array;
	$q  = "UPDATE ostats set ";
	$q .= sprintf("rank=%d, level=%d, attack=%d, defense=%d, health=%d ",
		$rank, $level, $attack, $defense, $health);
	$q .= " where player_id = ${player_id} and officer_id = ${officer_id}";
	$qret = $bot->{db}->doquery($q);
	my $rstr = "Updated ${shortname} bits!\n";
	if ($orank != $rank) {
		$rstr .= "Rank ${orank} -> ${rank}\n";
	}
	if ($olevel != $level) {
		$rstr .= "Level ${olevel} -> ${level}\n";
	}
	if ($oattack != $attack) {
		$rstr .= "Attack ${oattack} -> ${attack}\n";
	}
	if ($odefense != $defense) {
		$rstr .= "Defense ${odefense} -> ${defense}\n";
	}
	if ($ohealth != $health) {
		$rstr .= "Health ${ohealth} -> ${health}\n";
	}
	return $rstr;
}

1;
