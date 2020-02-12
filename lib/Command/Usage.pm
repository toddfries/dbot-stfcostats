package Command::Usage;

use v5.10;
use strict;
use warnings;

use Exporter qw(import);
our @EXPORT_OK = qw(cmd_usage);

use Mojo::Discord;
use Bot::Framework;
use Data::Dumper;

###########################################################################################
# Command Usage
my $command = "Usage";
my $access = 0; # Public
my $description = "Display information about the bot, including framework, creator, and source code";
my $pattern = '^(show help|usage)$';
my $function = \&cmd_usage;
my $usage = <<EOF;
Usage: `stats faq
i <shortname> <rank> <level> <attack> <defense> <health>
q <shortname>
q <cmd> <count> <args>
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
        'command'       => $command,
        'access'        => $access,
        'description'   => $description,
        'usage'         => $usage,
        'pattern'       => $pattern,
        'function'      => $function,
        'object'        => $self,
    );
    
    return $self;
}

sub cmd_usage
{
    my ($self, $channel, $author) = @_;

    my $discord = $self->{'discord'};
    my $bot = $self->{'bot'};

    my $usage;
    
    # We can use some special formatting with the webhook.
    if ( my $hook = $bot->has_webhook($channel) )
    {
        $usage = "**Usage**\n" .
                "hit me - get dealt a sector to search\n" .
                "usage  - this usage info, aka 'show me help'\n";

        $discord->send_webhook($channel, $hook, $usage);
                
    }
    else
    {
        $usage = "**Usage**\n" .
                "hit me - get dealt a sector to search\n" .
                "usage  - this usage info, aka 'show me help'\n";

        $discord->send_message($channel, $usage);
    }
}

1;
