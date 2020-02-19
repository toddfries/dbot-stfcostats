package Bot::Framework;

use v5.10;
use strict;
use warnings;

use Data::Dumper;
use Mojo::Discord;
use Mojo::IOLoop;

use FDC::db;
use DBD::Pg; # only to use PG_BYTEA
use POSIX qw(getpid);

use Exporter qw(import);
our @EXPORT_OK = qw(add_command command get_patterns);

sub new
{
    my ($class, %params) = @_;
    my $self = {};
    bless $self, $class;

    $self->{'commands'} = {};
    $self->{'patterns'} = {};

    $self->{'discord'} = Mojo::Discord->new(
        'token'     => $params{'discord'}->{'token'},
        'name'      => $params{'discord'}->{'name'},
        'url'       => $params{'discord'}->{'redirect_url'},
        'version'   => '1.0',
        'bot'       => $self,
        'callbacks' => {    # Discord Gateway Dispatch Event Types
            'READY'             => sub { $self->discord_on_ready(shift) },
            'GUILD_CREATE'      => sub { $self->discord_on_guild_create(shift) },
            'GUILD_UPDATE'      => sub { $self->discord_on_guild_update(shift) },
            'GUILD_DELETE'      => sub { $self->discord_on_guild_delete(shift) },
            'CHANNEL_CREATE'    => sub { $self->discord_on_channel_create(shift) },
            'CHANNEL_UPDATE'    => sub { $self->discord_on_channel_update(shift) },
            'CHANNEL_DELETE'    => sub { $self->discord_on_channel_delete(shift) },
            'TYPING_START'      => sub { $self->discord_on_typing_start(shift) }, 
            'MESSAGE_CREATE'    => sub { $self->discord_on_message_create(shift) },
            'MESSAGE_UPDATE'    => sub { $self->discord_on_message_update(shift) },
            'PRESENCE_UPDATE'   => sub { $self->discord_on_presence_update(shift) },
            'WEBHOOKS_UPDATE'   => sub { $self->discord_on_webhooks_update(shift) },
        },
        'reconnect' => $params{'discord'}->{'auto_reconnect'},
        'verbose'   => $params{'discord'}->{'verbose'},
    );
    
    $self->{'owner_id'} = $params{'discord'}->{'owner_id'};
    $self->{'trigger'} = $params{'discord'}->{'trigger'};
    $self->{'playing'} = $params{'discord'}->{'playing'};
    $self->{'client_id'} = $params{'discord'}->{'client_id'};
    $self->{'webhook_name'} = $params{'discord'}->{'webhook_name'};
    $self->{'webhook_avatar'} = $params{'discord'}->{'webhook_avatar'};
    $self->{'faqfile'} = $params{'discord'}->{'faqfile'};

    $self->{'dbtype'} = $params{'discord'}->{'dbtype'};
    $self->{'dbhost'} = $params{'discord'}->{'dbhost'};
    $self->{'dbname'} = $params{'discord'}->{'dbname'};
    $self->{'dbuser'} = $params{'discord'}->{'dbuser'};
    $self->{'dbpass'} = $params{'discord'}->{'dbpass'};
    if (defined($self->{'dbhost'}) && defined($self->{'dbname'})) {
	$self->{dsn} = sprintf("%s:dbname=%s;host=%s",
		$self->{dbtype},
		$self->{dbname},
		$self->{dbhost});
    	$self->{db} = FDC::db->new(
		$self->{dsn},
		$self->{dbuser},
		$self->{dbpass},
	);
    	if (!defined($self->{db})) {
		return undef;
    	}
	$self->{stats} = { };
	$self->{stats}->{pgct} = 0;
    }
    $self->{debug} = $params{debug};

    if (!defined($self->{debug})) {
		$self->{debug} = 0;
    }

    return $self;
}

# Connect to discord and start running.
sub start
{
    my $self = shift;

    $self->init_db();
    $self->{'discord'}->init();
    
    # Start the IOLoop unless it is already running. 
    Mojo::IOLoop->start unless Mojo::IOLoop->is_running; 
}

sub init_db
{
	my ($self) = @_;

	if (!defined($self->{'db'})) {
		# we failed to init in new() so fail gracefully here
		return;
	}

	my @tables;

	my $d = $self->{'db'};

	my $dbmsname = $d->getdbh()->get_info( 17 );
	my $dbmsver  = $d->getdbh()->get_info( 18 );

	my ($serialtype,$blobtype,$tablere,$index_create_re);

	if ($dbmsname eq "PostgreSQL") {
		$serialtype = "serial";
		$blobtype = "bytea";
		$tablere = '\\.%name%$';
		$self->{stats}->{pgsz} = 1;
		my $get_dbsz  = "SELECT  pg_database_size(datname) db_size ";
		$get_dbsz .= "FROM pg_database where datname = '";
		$get_dbsz .= $self->{dbname};
		$get_dbsz .= "' ORDER BY db_size";
		$self->{get_dbsz} = $get_dbsz;
		my $blob_bind_type = { pg_type => PG_BYTEA };
		$self->{blob_bind_type} = $blob_bind_type;
		$index_create_re  = "CREATE INDEX %NAME% ON %TABLE% using ";
		$index_create_re .= "btree ( %PARAMS% )";
		$d->do("SET application_name = 'stfcstatsbot/".getpid()."'");
	} else {
		print "db: Unknown dbmsname and version ${dbmsname} ${dbmsver}\n";
		return;
	}

	$self->{stats}->{pgct} = $d->do_oneret_query($self->{get_dbsz});

	@tables = $d->tables();
	my %tablefound;

	printf "db: Tables found: %d\n", ($#tables + 1);

	foreach my $tname (@tables) {
		#printf "db: Checking dbms table '%s'\n", $tname;
		foreach my $tn (('players','officers','ostats')) {
			my $tre = $tablere;
			$tre =~ s/%name%/$tn/g;
			if ($tname =~ m/$tre/) {
				printf "db: Matched '%s' to our table '%s' via tablere '%s'\n",
					$tname, $tn, $tre;
				$tablefound{$tn} = 1;
			}
		}
	}

	if (!defined($tablefound{'players'})) {
		print "db: Creating players table\n";
		my $q = "CREATE TABLE players (";
		$q .= "id ${serialtype}, ";
		$q .= "did TEXT, ";
		$q .= "addtime timestamp without time zone DEFAULT now()";
		$q .= ") with oids";
		my $sth = $d->doquery($q);
	}
	if (!defined($tablefound{'player_stats'})) {
		print "db: Creating player_stats table\n";
		my $q = "CREATE TABLE player_stats (";
		$q .= "id ${serialtype}, ";
		$q .= "academy INT, ";
		$q .= "adv_train INT, ";
		$q .= "attack_train INT, ";
		$q .= "defense_train INT ";
		$q .= ") with oids";
		my $sth => $d->doquery($q);
	}
	if (!defined($tablefound{'officers'})) {
		print "db: Creating officers table\n";
		my $q = "CREATE TABLE officers (";
		$q .= "id ${serialtype}, ";
		$q .= "short TEXT, ";
		$q .= "long TEXT, ";
		$q .= "cap_maneauver TEXT, ";
		$q .= "off_ability TEXT, ";
		$q .= "addtime timestamp without time zone DEFAULT now()";
		$q .= ") with oids";
		my $sth = $d->doquery($q);
	}
	if (!defined($tablefound{'ostats'})) {
		print "db: Creating ostats table\n";
		my $q = "CREATE TABLE ostats (";
		$q .= "id ${serialtype}, ";
		$q .= "player_id INTEGER, ";
		$q .= "officer_id INTEGER, ";
		$q .= "rank INTEGER, ";
		$q .= "level INTEGER, ";
		$q .= "attack INTEGER, ";
		$q .= "defense INTEGER, ";
		$q .= "health INTEGER, ";
		$q .= "addtime timestamp without time zone DEFAULT now()";
		$q .= ") with oids";
		my $sth = $d->doquery($q);
	}
}



sub discord_on_ready
{
    my ($self, $hash) = @_;

    $self->add_me($hash->{'user'});
    
    #$self->{'discord'}->status_update({'game' => $self->{'playing'}});

    say localtime(time) . " Connected to Discord.";

    #say Dumper($hash);
}

sub discord_on_guild_create
{
    my ($self, $hash) = @_;

    say "Adding guild: " . $hash->{'id'} . " -> " . $hash->{'name'};

    $self->add_guild($hash);

    #say Dumper($hash);
}

sub discord_on_guild_update
{
    my ($self, $hash) = @_;

    # Probably just use add_guild here too.
}

sub discord_on_guild_delete
{
    my ($self, $hash) = @_;

    # Remove the guild
}

sub discord_on_channel_create
{
    my ($self, $hash) = @_;

    # Create the channel
}

sub discord_on_channel_update
{
    my ($self, $hash) = @_;

    # Probably just call the same as on_channel_create does
}

sub discord_on_channel_delete
{
    my ($self, $hash) = @_;

    # Remove the channel
}

# Whenever we get this we should request the webhooks for the channel.
# The only one we care about is the one we created.
sub discord_on_webhooks_update
{
    my ($self, $hash) = @_;

    my $channel = $hash->{'channel_id'};
    delete $self->{'webhooks'}{$channel};

    $self->cache_channel_webhooks($channel);
}

sub discord_on_typing_start
{
    my ($self, $hash) = @_;

    # Not sure if we'll ever do anything with this event, but it's here in case we do.
}

sub discord_on_message_create
{
    my ($self, $hash) = @_;

    my $author = $hash->{'author'};
    my $name = "<undef>";
    my $msg = $hash->{'content'};
    my $cid = $hash->{'channel_id'};
    my $member  = $self->uid_to_member($cid,$author);
    my ($aname, $anick) = ("<undef>", "<undef>");
    if (defined($member) && ref($member) ne "") {
	my $user = $member->{'user'};
        $aname = $user->{'username'}.'#'.$member->{'user'}->{discriminator};
	if (defined($member->{nick})) {
    		$anick = $member->{'nick'};
	} else {
		$anick = $aname;
	}
    } 
    my $channel = $self->get_channel($cid);
    my $cname;
    if (defined($channel)) {
    	$cname = $channel->{name};
    } else {
	$cname = $cid;
    }
    my @mentions = @{$hash->{'mentions'}};
    my $trigger = $self->{'trigger'};
    my $discord_name = $self->name();
    my $discord_id = $self->id();
    my $guild = $self->cid_to_guild($cid);
    my $gname = "<undef>";
    if (defined($guild)) {
    	$gname = $guild->{name};
    }

    foreach my $mention (@mentions)
    {
        $self->add_user($mention);
    }
    print "message: ${aname}($anick)\@${gname}#${cname}: '${msg}'\n";
    #print "\$hash: ".Dumper($hash);
    #print "\$self: ".Dumper($self);

    if (defined($author->{'bot'}) and $author->{'bot'}) { 
	printf "Bot msg: author->{bot} = '%s'\n", $author->{'bot'};
    } else {
        # Send 'Hello, World!' back
        #my $replyto = '<@' . $author->{id} . '>';
        #$self->{discord}->send_message($cid, "Hello World, ${replyto}!");

	if (!defined($msg)) {
		return;
	}
        # Get all command patterns and iterate through them.
        # If you find a match, call the command fuction.
        foreach my $pattern ($self->get_patterns())
        {
	    if ($self->{debug} > 0) {
		printf "msg '%s' vs re /%s/i\n", $msg, $pattern;
	    }
            if ( $msg =~ /$pattern/i )
            {
                my $command = $self->get_command_by_pattern($pattern);
                my $access = $command->{'access'};
                my $owner = $self->owner;

		if ($self->{debug} > 0) {
			printf "msg matched command '%s' { %s }->{access} = '%s'\n",
				$command->{command}, $command, $access;
			#print Dumper($command);
		}

                if ( defined $access and $access > 0 and defined $owner and $owner != $author->{'id'} )
                {
                    # Sorry, no access to this command.
                    say localtime(time) . ": '" . $author->{'username'} . "' (" . $author->{'id'} . ") tried to use a restricted command and is not the bot owner.";
                }
                elsif ( ( defined $access and $access == 0 ) or ( defined $owner and $owner == $author->{'id'} ) )
                {
                    my $object = $command->{'object'};
                    my $function = $command->{'function'};
                    $object->$function($cid, $author, $msg);
                }
            }
        }
    }
	

    # Look for messages starting with a mention or a trigger, but not coming from a bot.
    if ( !(exists $author->{'bot'} and $author->{'bot'}) and $msg =~ /^(\<\@\!?$discord_id\>|\Q$trigger\E)/i )
    {
        $msg =~ s/^((\<\@\!?$discord_id\>.? ?)|(\Q$trigger\E))//i;   # Remove the username. Can I do this as part of the if statement?

        if ( defined $msg )
        {
            # Get all command patterns and iterate through them.
            # If you find a match, call the command fuction.
            foreach my $pattern ($self->get_patterns())
            {
                if ( $msg =~ /$pattern/i )
                {
                    my $command = $self->get_command_by_pattern($pattern);
                    my $access = $command->{'access'};
                    my $owner = $self->owner;

                    if ( defined $access and $access > 0 and defined $owner and $owner != $author->{'id'} )
                    {
                        # Sorry, no access to this command.
                        say localtime(time) . ": '" . $author->{'username'} . "' (" . $author->{'id'} . ") tried to use a restricted command and is not the bot owner.";
                    }
                    elsif ( ( defined $access and $access == 0 ) or ( defined $owner and $owner == $author->{'id'} ) )
                    {
                        my $object = $command->{'object'};
                        my $function = $command->{'function'};
                        $object->$function($cid, $author, $msg);
                    }
                }
            }
        }
    }
}

sub discord_on_message_update
{
    my ($self, $hash) = @_;

    # Might be worth checking how old the message is, and if it's recent enough re-process it for commands?
    # Would let people fix typos without having to send a new message to trigger the bot.
    # Have to track replied message IDs in that case so we don't reply twice.
}

sub discord_on_presence_update
{
    my ($self, $hash) = @_;

    # Will be useful for a !playing command to show the user's currently playing "game".
}

sub cache_channel_webhooks
{
    my ($self, $channel, $callback) = @_;
   
    $self->{'discord'}->get_channel_webhooks($channel, sub
    {
        my $json = shift;

        my $hookname = $self->webhook_name;

        foreach my $hook (@{$json})
        {
            if ( $hook->{'name'} eq $self->webhook_name )
            {
                $self->{'webhooks'}{$channel} = $hook;
            }
        }
    });
}

sub cache_guild_webhooks
{
    my ($self, $guild, $callback) = @_;

    my $id = $guild->{'id'};

    $self->{'discord'}->get_guild_webhooks($id, sub
    {
        my $json = shift;
        #say  Dumper($json);

        if ( ref $json eq ref {} and $json->{'code'} == 50013 )
        {
            # No Access.
            return;
        }

        my $hookname = $self->webhook_name;

        foreach my $hook (@{$json})
        {
            my $channel = $hook->{'channel_id'};
            if ( $hook->{'name'} eq $self->webhook_name )
            {
                $self->{'webhooks'}{$channel} = $hook;
            }
        }
    });
}

sub add_me
{
    my ($self, $user) = @_;
    say "Adding my ID as " . $user->{'id'};
    $self->{'id'} = $user->{'id'};
    $self->add_user($user);
}

sub id
{
    my $self = shift;

    return $self->{'id'};
}

sub name
{
    my $self = shift;
    return $self->{'users'}{$self->id}->{'username'}
}

sub discriminator
{
    my $self = shift;
    return $self->{'users'}{$self->id}->{'discriminator'};
}

sub client_id
{
    my $self = shift;
    return $self->{'client_id'};
}

sub my_user
{
    my $self = shift;
    my $id = $self->{'id'};
    return $self->{'users'}{$id};
}

sub add_user
{
    my ($self, $user) = @_;
    my $id = $user->{'id'};
    $self->{'users'}{$id} = $user;
}

sub get_user
{
    my ($self, $id) = @_;
    return $self->{'users'}{$id};
}

sub uid_to_member
{
    my ($self, $cid, $author) = @_;
    my $uid = $author->{id};
    my $guildid =  $self->{'channels'}{$cid};
    if (!defined($guildid)) {
	return;
    }
    my @members = @{$self->{guilds}->{$guildid}->{members}};
    #print Dumper($uid);
    #print "looking for user id ${uid}\n";
    foreach my $mem (@members) {
        #print "mem->{user}->{id/username} = ".$mem->{user}->{id}."/".$mem->{user}->{username}."\n";
	if ($mem->{user}->{id} == $uid) {
	#	print "match!\n";
		return $mem;
	}
    }
}

sub get_channel
{
    my ($self, $id) = @_;
    my $guildid =  $self->get_guild_by_channel($id);
    if (!defined($guildid)) {
	return undef;
    }
    my @channels = @{$self->{guilds}->{$guildid}->{channels}};
    foreach my $chan (@channels) {
	if ($chan->{id} == $id) {
		return $chan;
	}
    }
}

sub cid_to_guild
{
    my ($self, $cid) = @_;
    my $guildid =  $self->get_guild_by_channel($cid);
    if (!defined($guildid)) {
	return undef;
    }
    print "cid_to_guild: cid=${cid}\n";
    my $guild = $self->{guilds}->{$guildid};
    #print Dumper($guild);
    return $guild;
}

sub remove_user
{
    my ($self, $id) = @_;

    delete $self->{'users'}{$id};
}


# Tell the bot it has connected to a new guild.
sub add_guild
{
    my ($self, $guild) = @_;

    # Nice and simple. Just add what we're given.
    $self->{'guilds'}{$guild->{'id'}} = $guild;

    # Also, let's request the webhooks for this guild.
    $self->cache_guild_webhooks($guild);

    # Also add entries for channels in this guild.
    foreach my $channel (@{$guild->{'channels'}})
    {
        $self->{'channels'}{$channel->{'id'}} = $guild->{'id'};
	my $type = $channel->{type};
	my $ctype = $self->{'discord'}->ctype_to_name($type);
	my $cname = $channel->{name};
	#printf "              channel %s -> %8s %s\n", $channel->{id}, $ctype, $channel->{name};
	if (0 && $type == 0 && $cname =~ /test/ ) { # for now disble, iterating through all channels every start, not good
        $self->{'discord'}->get_channel_messages($channel,sub
	{
		my $json = shift;
		my $channel = shift;
		my $cid = $channel->{id};
		print "channel ${cid} messages: ".Dumper($json);
		sleep(1);
	}, 'limit' => 3);
	}
    }
}

sub get_guild_by_channel
{
    my ($self, $channel) = @_;

    return $self->{'channels'}{$channel};
}

sub remove_guild
{
    my ($self, $id) = @_;

    delete $self->{'guilds'}{$id} if exists $self->{'guilds'}{$id};
}

# Return a single guild by ID
sub get_guild
{
    my ($self, $id) = @_;

    exists $self->{'guilds'}{$id} ? return $self->{'guilds'}{$id} : return undef;
}

# Return the list of guilds.
sub get_guilds
{
    my $self = shift;

    return keys %{$self->{'guilds'}};
}

sub get_patterns
{
    my $self = shift;
    return keys %{$self->{'patterns'}};
}

# Return a list of all commands
sub get_commands
{
    my $self = shift;

    my $cmds = {};
    
    foreach my $key (keys %{$self->{'commands'}})
    {
        $cmds->{$key} = $self->{'commands'}->{$key}{'description'};
    }

    return $cmds;
}

sub get_command_by_name
{
    my ($self, $name) = @_;

    return $self->{'commands'}{$name};
}

sub get_command_by_pattern
{
    my ($self, $pattern) = @_;

    return $self->get_command_by_name($self->{'patterns'}{$pattern});
}

# Return the bot's trigger prefix
sub trigger
{
    my $self = shift;
    return $self->{'trigger'};
}

# Command modules can use this function to register themselves with the bot.
# - Command
# - Access Level Required (Default 0 - public, 1 - Bot Owner)
# - Description
# - Usage
# - Pattern
# - Function
sub add_command
{
    my ($self, %params) = @_;

    my $command = lc $params{'command'};
    my $access = $params{'access'};
    my $description = $params{'description'};
    my $usage = $params{'usage'};
    my $pattern = $params{'pattern'};
    my $function = $params{'function'};
    my $object = $params{'object'};

    $self->{'commands'}->{$command}{'name'} = ucfirst $command;
    $self->{'commands'}->{$command}{'access'} = $access;
    $self->{'commands'}->{$command}{'usage'} = $usage;
    $self->{'commands'}->{$command}{'description'} = $description;
    $self->{'commands'}->{$command}{'pattern'} = $pattern;
    $self->{'commands'}->{$command}{'function'} = $function;
    $self->{'commands'}->{$command}{'object'} = $object;

    $self->{'patterns'}->{$pattern} = $command;

    say localtime(time) . " Registered new command: '$command' identified by '$pattern'";
}

# This sub calls any of the registered commands and passes along the args
# Returns 1 on success or 0 on failure (if command does not exist)
sub command
{
    my ($self, $command, $args) = @_;

    $command = lc $command;

    if ( exists $self->{'commands'}{$command} )
    {
        $self->{'commands'}{$command}{'function'}->($args);
        return 1;
    }
    return 0;
}

# Returns the owner ID for the bot
sub owner
{
    my $self = shift;
    return $self->{'owner_id'};
}

# Return the webhook name the bot will use
sub webhook_name
{
    my $self = shift;
    return $self->{'webhook_name'};
}

sub webhook_avatar
{
    my $self = shift;
    return $self->{'webhook_avatar'};
}

# Check if a webhook already exists - return it if so.
# If not, create one and add it to the webhooks hashref.
# Is non-blocking if callback is defined.
sub create_webhook
{
    my ($self, $channel, $callback) = @_;

    return $_ if ( $self->has_webhook($channel) );

    # Create a new webhook
    my $discord = $self->discord;

    my $params = {
        'name' => $self->webhook_name, 
        'avatar' => $self->webhook_avatar 
    };

    if ( defined $callback )
    {
        $discord->create_webhook($channel, $params, sub
        {
            my $json = shift;

            if ( defined $json->{'name'} ) # Success
            {
                $callback->($json);
            }
            elsif ( $json->{'code'} == 50013 ) # No permission
            {
                say localtime(time) . ": Unable to create webhook in $channel - Need Manage Webhooks permission";
                $callback->(undef);
            }
            else
            {
                say localtime(time) . ": Unable to create webhook in $channel - Unknown reason";
                $callback-(undef);
            }
        });
    }
    else
    {
        my $json = $discord->create_webhook($channel); # Blocking

        return defined $json->{'name'} ? $json : undef;
    }
}

sub add_webhook
{
    my ($self, $channel, $json) = @_;

    $self->{'webhooks'}{$channel} = $json;
    return $self->{'webhooks'}{$channel};
}

# This retrieves a cached webhook object for the specified channel.
# If there isn't one, return undef and let the caller go make one or request an existing one from Discord.
sub has_webhook
{
    my ($self, $channel) = @_;

    if ( exists $self->{'webhooks'}{$channel} )
    {
        return $self->{'webhooks'}{$channel};
    }
    else
    {
        return undef;
    }
}

# Returns the discord object associated to this bot.
sub discord
{
    my $self = shift;
    return $self->{'discord'};
}

1;
