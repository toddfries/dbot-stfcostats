package Command::q;

use v5.10;
use strict;
use warnings;

use Exporter qw(import);
our @EXPORT_OK = qw(cmd_q);

use Bot::Framework;
use Data::Dumper;
use Discord::Players;
use Discord::Send;
use Mojo::Discord;

###########################################################################################
# Command q
my $command = "q";
my $access = 0; # Public
my $description = "Display information about the bot, including framework, creator, and source code";
my $pattern = '^q\s([a-z]+\s[0-9]+\s[a-z]+[a-z\+]+|[a-z][a-z0-9\_\`]+)$';
my $function = \&cmd_q;
my $usage = <<EOF;
Usage:
 `q <command> <count> <algo>`
   .. command = top
   .. algo = attack, health, defense, combo
   -or-
 `q <shortname>`
   -or-
 `q all`
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

sub cmd_q
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

	$info = "From the stats database of ${user} we have:\n";

	my @bits;
	foreach my $m (split(/^/,$msg)) {
	@bits = split(/\s+/,$m);
	if ($bits[0] =~ /^q$/i) {
		if ($#bits == 3) {
			$info .= sprintf("\nQuery parsed as: cmd='%s', count=%d, op=%s\n", $bits[1], $bits[2], $bits[3]);
			$info .= $self->query($id, @bits);
		} elsif ($#bits == 1 && $bits[1] eq "all") {
			$info .= sprintf("\nQuery parsed as: all -> top 1000 attack\n");
			$bits[1] = "top";
			$bits[2] = "1000";
			$bits[3] = "atack";
			$info .= $self->query($id, @bits);
		} elsif ($#bits == 1) {
			$info .= sprintf("\nQuery parsed as: officer='%s'\n", lc($bits[1]));
			$info .= $self->show_stats($id, @bits);
		} else {
			$info .= $usage;
		}
	} else {
		$info .= $usage;
	}
	}
	

	$self->{send}->send($channel, $info);
}

sub query {
	my ($self, $player_id, $qcmd, $cmd, $count, $op) = @_;
	my $bot = $self->{bot};
	my $db  = $bot->{db};

	my ($sort);

	# q top 5 strength	
	if ($cmd eq "top") {
		$sort = "desc";
	} else {
		$sort = "asc";
	}
	my $order = "order by ";

	if ($bot->{debug} > 0) {
		print "op: $op\n";
	}
	my ($attack,$defense,$health,$strength) = (0,0,0,0);
	if ($op =~ /attack/) {
		$attack = 1;
	}
	if ($op =~ /defense/) {
		$defense = 1;
	}
	if ($op =~ /health/) {
		$health = 1;
	}
	if ($op =~ /strength/) {
		$strength = 1;
	}

	my $counter = 0;
	if (($health + $defense + $attack) == 2) {
		if ($health > 0 && $defense > 0) {
			$order .= " (def_on_ship + hea_on_ship) ";
			$counter++;
			$health = 0;
			$defense = 0;
		}
		if ($health > 0 && $attack > 0) {
			$order .= " ((s.attack*(s.rank+1)) + (s.health*(s.rank+1))) ";
			$counter++;
			$health = 0;
			$attack = 0;
		}
		if ($defense > 0 && $attack > 0) {
			$order .= " (att_on_ship + def_on_ship) ";
			$counter++;
			$defense = 0;
			$attack = 0;
		}
	} else {
		if ($health > 0) {
			$order .= "hea_on_ship ";
			$counter++;
		}
		if ($defense > 0) {
			if ($counter++ > 0) {
				$order .= ",";
			}
			$order .= "def_on_ship ";
		}
		if ($attack > 0) {
			if ($counter++ > 0) {
				$order .= ",";
			}
			$order .= "att_on_ship ";
		}
	}
	if ($strength > 0) {
		if ($counter++ > 0) {
			$order .= ",";
		}
		$order .= "strength_on_ship ";
	}
	
	my $qlim = " where ";
	$qlim .= "s.player_id = $player_id and ";
	$qlim .= "s.officer_id = o.id and ";
	$qlim .= "ps.player_id = $player_id ";
	$qlim .= " $order $sort ";
	$qlim .= " limit ${count}";

	$self->_stats_fmt($qlim);
}

sub show_stats {
	my ($self, $player_id, $tmp, $short) = @_;
	my $bot = $self->{bot};
	my $db  = $bot->{db};

	my $qlim = " where ";
	$qlim .= "s.player_id = $player_id and ";
	$qlim .= "s.officer_id = o.id and ";
	$qlim .= "ps.player_id = $player_id ";

	$self->_stats_fmt($qlim);
}

sub _stats_fmt {
	my ($self, $qlim) = @_;
	my $bot = $self->{bot};
	my $db  = $bot->{db};
	my $str = "";

	my $q = "select o.short, s.rank, s.level, ";
	$q .= "s.attack, s.defense, s.health, ";
	$q .= "(s.attack+s.defense+s.health)*(1+s.rank) as strength, ";
	$q .= "(s.attack*(s.rank+1))*(1+ps.academy*.01) as att_on_ship, ";
	$q .= "(s.defense*(s.rank+1))*(1+ps.academy*.01) as def_on_ship, ";
	$q .= "(s.health*(s.rank+1))*(1+ps.academy*.01) as hea_on_ship, ";
	$q .= "((s.attack+s.defense+s.health)*(1+ps.academy*.01)*(s.rank+1)) as strength_on_ship ";
	$q .= "from officers as o, ostats as s, player_stats as ps ";

	$q .= $qlim;

	if ($bot->{debug} > 0) {
		print "q: ${q}\n";
		$str .= "sql query:${q}\n";
	}

	my $sth = $db->doquery($q);
	if (!defined($sth) || $sth == -1) {
		return "Something went wrong, please contact Spuds\n";
	}
	my $rv = $sth->rows;

	if ($rv < 1) {
		return "0 info returned\n";
	}

	my ($short, $rank, $level);
	my $i = 0;
	$str .= sprintf "`.                              Station                  Ship`\n";
	$str .= sprintf "`.    %15s%3s%3s%5s%5s%5s%6s  %5s%5s%5s %s`\n",
		"Short","R","L","Att","Def","Hea", "Str.", "Att", "Def", "Hea", "Strength";
			
	my ($attack, $defense, $health, $strength);
	my ($sattack, $sdefense, $shealth, $sstrength);
	while (($short, $rank, $level, $attack, $defense, $health,
		$strength, $sattack, $sdefense, $shealth, $sstrength)
		= $sth->fetchrow_array) {
		if (!defined($sattack)) {
			$sattack = -1;
		}
		if (!defined($sdefense)) {
			$sdefense = -1;
		}
		if (!defined($shealth)) {
			$shealth = -1;
		}
		if (!defined($sstrength)) {
			$sstrength = -1;
		}
		$i++;
		$str .= sprintf "`.%2d. %15s %2d %2d %4d %4d %4d %5d   %4d %4d %4d %5d`\n", 
			$i, $short, $rank, $level,
			$attack, $defense, $health, $strength,
			$sattack, $sdefense, $shealth, $sstrength;
	}
	return $str;
}

1;
