#!/usr/bin/env perl
package main;

use strict;
use warnings;

use List::Util qw(max);
use Term::ANSIColor qw(:constants colorstrip);


use constant COMMANDS_FILE => "$ENV{HOME}/.launcher-commands.yaml";
use constant TEXT_EDITOR => "nano --tabsize=4 --autoindent --linenumbers {file}";
use constant DISABLED_INTERNAL_COMMANDS => [];


our $USER_COMMANDS = {};
our $USER_VARIABLES = {};
our $INNER_COMMANDS = InternalCommands->new($USER_COMMANDS, $USER_VARIABLES);

our $ALIAS_DEF_REGEXP = qr/^([a-z](?:[a-z0-9_-]*[a-z0-9])?)$/i;
our $ENV_DEF_REGEXP   = qr/^\^([A-Z](?:[A-Z0-9_]*[A-Z0-9])?)$/;
our $VAR_DEF_REGEXP   = qr/^\$([a-z](?:[a-z0-9_-]*[a-z0-9])?)$/i;
our $ENV_USE_REGEXP   = qr/([A-Z](?:[A-Z0-9_]*[A-Z0-9])?)$/;
our $VAR_USE_REGEXP   = qr/(\\?)\$\{([a-z](?:[a-z0-9_-]*[a-z0-9])?)\}/i;
our $OPT_USE_REGEXP   = qr/(\\?)\$(\d+)/;


sub check_commands_file
{
	if(!-e COMMANDS_FILE){
		my ($dev, $app, $ver) = (Utils::APP_DEV(), Utils::APP_NAME(), Utils::APP_VER());
		my $file = COMMANDS_FILE;
		open my $fh, ">", $file or Utils->print_msg("ERROR", "Cannot create $file: $!", Utils::THEN_DIE());
		my $yaml = <<"LAUNCHER_COMMANDS_YAML";
# $dev $app $ver | Commands File
#
# Root keys should follow these rules:
# 1. Root keys started with "\$" set variables (See README.md file)
# 2. Root keys started with "\^" set env variables (See README.md file)
# 3. Variables could have any value
# 4. Environment variables should be scalar (string or number)
# 5. Aliases only have these sub-keys:
#    - cmd:  Required. It contains command(s) to run. Could be a string (semicolon separated) or a list.
#    - desc: Optional. Description about the command shown in "Usage" screen.
#    - meta: Optional. It's a list of strings and/or key:value pairs,
#            used to customize context of command execution.
#
# Available Meta:
# - "quiet" (turn quiet mode on for the command)
# - "clear" (clear screen before execute command)
# - "^<NAME>" (Set environment variable for command)
# - "\$<name>" (Set variable usable in command)

\$my_name: World

hello:
  cmd: echo "Hello \${my_name}!"
  meta: clear
  desc: Say hello to me

LAUNCHER_COMMANDS_YAML
		print $fh $yaml;
		close $fh;
	}
}


sub parse_commands_yaml
{
	my @docs = SimpleYAML->parse_file(COMMANDS_FILE);
	for my $doc (@docs) {
		for my $key (keys %$doc) {
			Utils->print_msg("ERROR", "Command alias should not starts with \"@\": $key", Utils::THEN_DIE()) if $key =~ /^\@/;
			if($key =~ /$VAR_DEF_REGEXP/){
				# Variable:
				$USER_VARIABLES->{$1} = $doc->{$key};
			}elsif($key =~ /$ENV_DEF_REGEXP/){
				# Env Varialbe:
				$ENV{$1} = $doc->{$key};
			}elsif($key =~ /$ALIAS_DEF_REGEXP/){
				# Command Alias:
				$doc->{$key} = { cmd => $doc->{$key} } if Utils->is_scalar($doc->{$key});
				Utils->print_msg("ERROR", "Command \"$key\" does not have \"cmd\" prop.", Utils::THEN_DIE()) unless defined $doc->{$key}->{cmd};
				Utils->print_msg("ERROR", "Prop \"cmd\" of command \"$key\" should defined as string or list of strings:\n" . Utils->dump($doc->{$key}->{cmd}), Utils::THEN_DIE()) unless Utils->is_scalar($doc->{$key}->{cmd}) || Utils->is_array_ref($doc->{$key}->{cmd});
				my $k = $1;
				my $cmd = $doc->{$key}->{cmd};
				$cmd = join("; ", @$cmd) if Utils->is_array_ref($cmd);
				$cmd =~ s/^;+|;+$//g;
				my $desc = defined $doc->{$key}->{desc} && Utils->is_scalar($doc->{$key}->{desc}) ? $doc->{$key}->{desc} : "";
				my $meta = HashMap->new();
				if(defined $doc->{$key}->{meta}){
					my $m = $doc->{$key}->{meta};
					if(Utils->is_scalar($m)){
						$meta->set($m => Utils::TRUE());
					}elsif(Utils->is_array_ref($m)){
						for my $x (@$m){
							if(Utils->is_scalar($x)){
								$meta->set($x => Utils::TRUE());
							}elsif(Utils->is_hash_ref($x)){
								for my $y (keys %$x){
									if(Utils->is_scalar($x->{$y})){
										$meta->set($y => $x->{$y});
									}else{
										Utils->print_msg("ERROR", "Value of meta \"$y\" of command \"$key\" is not a scalar.", Utils::THEN_DIE());
									}
								}
							}else{
								Utils->print_msg("ERROR", "Value of meta \"$x\" of command \"$key\" is not a scalar nor a hash.", Utils::THEN_DIE());
							}
						}
					}else{
						Utils->print_msg("ERROR", "Prop \"meta\" of command \"$key\" is not a string nor a list.", Utils::THEN_DIE());
					}
				}
				$USER_COMMANDS->{$k} = { cmd => $cmd, desc => $desc, meta => $meta };
			}
		}
	}
}


sub apply_env_variables
{
	my ($vars) = @_;
	for my $k (keys %$vars){ $ENV{$k} = $vars->{$k}; }
}


sub apply_user_variables
{
	my ($vars) = @_;
	for my $k (keys %$vars){ $USER_VARIABLES->{$k} = $vars->{$k}; }
}


sub replace_variables
{
	my ($str, $what) = @_;
	my $vars_hash = Utils->get_option("vars")->to_hash();
	my $match = sub {
		my ($type, $esc, $key) = @_;
		if($type eq 'VAR'){
			if($esc){ return "\${$key}"; }
			my $val = Utils->get_variable($key, $vars_hash);
			unless(defined $val){ $val = Utils->get_variable($key, $USER_VARIABLES); }
			return (!ref($val) && defined($val) ? $val : "");
		}elsif($type eq 'OPT'){
			if($esc){ return "\$$key"; }
			my $opts = Utils->get_option("opts");
			return ($key eq "0" ? join(' ', @$opts) : defined($opts->[$key - 1]) ? $opts->[$key - 1] : "");
		}
		return "";
	};
	if(!$what || $what eq 'VAR'){ $str =~ s/$VAR_USE_REGEXP/$match->('VAR', $1, $2)/eg; }
	if(!$what || $what eq 'OPT'){ $str =~ s/$OPT_USE_REGEXP/$match->('OPT', $1, $2)/eg; }
	return $str;
}


sub parse_meta_vars
{
	my ($meta) = @_;
	if($meta->isa('HashMap')){
		my $other = HashMap->new();
		$meta->for_each(sub {
			my ($v, $k) = @_;
			if($k =~ /$VAR_DEF_REGEXP/i){ $USER_VARIABLES->{$1} = replace_variables($v); }else{ $other->set($k, $v); }
		});
		return $other;
	}
}

sub parse_meta_envs
{
	my ($meta) = @_;
	if($meta->isa('HashMap')){
		my $other = HashMap->new();
		$meta->for_each(sub {
			my ($v, $k) = @_;
			if($k =~ /$ENV_DEF_REGEXP/){ $ENV{$1} = replace_variables($v); }else{ $other->set($k, $v); }
		});
		return $other;
	}
}


sub print_available_aliases
{
	return if Utils->get_option("quiet");
	# User Commands:
	if(keys %$USER_COMMANDS > 0){
		print "\nAvailable Aliases:\n";
		for(keys %$USER_COMMANDS){
			print " • ";
			print BRIGHT_CYAN, $_, RESET;
			print " ", YELLOW, "(", $USER_COMMANDS->{$_}->{desc}, ")", RESET if $USER_COMMANDS->{$_}->{desc};
			print "\n";
		}
	}
	# Internal Commands:
	print "\nInternal Commands:\n";
	for($INNER_COMMANDS->_keys()){
		next if $_ eq 'dev';
		print " • ";
		print BRIGHT_MAGENTA, "\@$_", RESET;
		print " ", YELLOW, "(", $INNER_COMMANDS->_desc($_), ")", RESET;
		print "\n";
	}
	# Options:
	print "\nOptions:\n";
	for my $row (@{Utils->list_options}){
		for(@{$row->{opt}}){ print "    ", BRIGHT_WHITE, $_, RESET, "\n"; }
		for(@{$row->{desc}}){ print " "x8, GREEN, $_, RESET, "\n"; }
	}
	print "\n";
}


sub print_usage
{
	Utils->print_title();
	Utils->print_msg("INFO", "Usage: run <alias> [<options>]");
	print_available_aliases();
	exit 0;
}


sub print_invalid_args
{
	my ($msg) = @_;
	Utils->print_title();
	Utils->print_msg("ERROR", $msg);
	print_available_aliases();
	exit 1;
}


sub execute_command
{
	my ($alias, $row) = @_;
	my $meta = parse_meta_vars($row->{meta}); # apply meta vars
	$meta = parse_meta_envs($meta); #apply meta envs
	Utils->get_option("envs")->for_each(sub { my ($v, $k) = @_; if($k =~ /^$ENV_USE_REGEXP$/){ $ENV{$1} = $v; } }); # apply cli envs
	$INNER_COMMANDS->clear() if $meta->get("clear");
	if($meta->get("quiet")){ Utils->set_option("quiet", Utils::TRUE()); }
	Utils->print_title();
	my $command = replace_variables(Utils->trim($row->{cmd}));
	$command =~ s/^;+|;+$//g;
	Utils->print(BRIGHT_GREEN, "➤ RUN: $command");
	my @all_commands = Utils->split_commands($command);
	for(@all_commands){
		my $cmd = $_;
		if($cmd =~ /^(?:run\s+)?(@\S+)/){
			$INNER_COMMANDS->_call($1);
		}elsif($cmd =~ /^cd/){
			$cmd =~ s/^cd\s+//;
			Utils->print(BRIGHT_CYAN, "✔ CWD: " . glob($cmd));
			chdir(glob($cmd));
		}else{
			if($cmd =~ /^run\s+([^\s]+)/){
				Utils->print_msg("ERROR", "A command could not run itself: $cmd", Utils::THEN_DIE()) if $1 eq $alias;
				$cmd .= " --sub-command";
			}
			Utils->bash($cmd);
		}
	}
}


sub run
{
	my ($alias) = @_;
	if($alias =~ /^@/){
		print_invalid_args("Internal command \"$alias\" not available.") unless $INNER_COMMANDS->_has($alias);
		execute_command($alias, { cmd => $alias, desc => $INNER_COMMANDS->_desc($alias), meta => HashMap->new() });
	}else{
		for(keys %$USER_COMMANDS){
			if($_ eq $alias){ execute_command($alias, $USER_COMMANDS->{$_}); return; }
		}
		print_invalid_args("A command with alias \"$alias\" not available.");
	}
}


sub main
{
	my $err = Utils->parse_options();
	if($err){ Utils->print_title(); print_invalid_args($err); }
	check_commands_file();
	parse_commands_yaml();
	$INNER_COMMANDS->clear() if Utils->get_option("clear");
	if(Utils->get_option("version")){ if(Utils->get_option("quiet")){ print(Utils::APP_VER(), "\n"); }else{ Utils->print_title(); } exit 0; }
	if(Utils->get_option("help")){ Utils->set_option("quiet", Utils::FALSE()); print_usage(); }
	if(Utils->get_option("alias")){ run(Utils->get_option("alias")); }else{ print_usage(); }
}


&main;


################################################################################
##  BUILT-IN PACKAGES
################################################################################


BEGIN {


	package Utils;

	use strict;
	use warnings;

	use Data::Dumper;
	use Term::ANSIColor qw(:constants);
	use Getopt::Long qw(:config gnu_getopt);

	use constant {
		FALSE      => 0,
		TRUE       => 1,
		APP_DEV    => "H8",
		APP_NAME   => "Launcher",
		APP_VER    => "1.1.0",
		APP_REPO   => "https://github.com/H8WebDev/Launcher",
		THEN_EXIT  => 0,
		THEN_DIE   => 1,
		ON_WINDOWS => "WINDOWS",
		ON_LINUX   => "LINUX",
		ON_MAC     => "MAC",
		ON_UNKNOWN => "UNKNOWN",
	};

	my $OPTIONS = {
		alias   => undef,  # The command alias to execute
		clear   => FALSE,  # --clear | -c
		subcmd  => FALSE,  # --sub-command
		quiet   => FALSE,  # --quiet | -q
		help    => FALSE,  # --help | -h | -?
		version => FALSE,  # --version | -v
		envs    => HashMap->new(), # --env name:value | --env=name:value | -E name:value
		vars    => HashMap->new(), # --var name:value | --var=name:value | -V name:value
		opts    => Array->new(),   # Other positional arguments
	};

	sub dump { my ($class, @args) = @_; my $dumper = Data::Dumper->new([ @args ]); $dumper->Indent(1)->Trailingcomma(1)->Purity(1); print $dumper->Dump; }

	sub is_scalar    { my ($class, $value) = @_; return !ref($value); }
	sub is_regexp    { my ($class, $value) = @_; return (ref($value) eq "Regexp"); }
	sub is_array_ref { my ($class, $value) = @_; return (ref($value) eq "ARRAY"); }
	sub is_hash_ref  { my ($class, $value) = @_; return (ref($value) eq "HASH"); }
	sub is_code_ref  { my ($class, $value) = @_; return (ref($value) eq "CODE"); }
	sub is_object    { my ($class, $value) = @_; return Scalar::Util::blessed($value); }
	sub is_number    { my ($class, $value) = @_; return Scalar::Util::looks_like_number($value); }

	sub trim         { my ($class, $input) = @_; if($input){ $input =~ s/^\s+|\s+$//g; } return $input; }
	sub trim_start   { my ($class, $input) = @_; if($input){ $input =~ s/^\s+//g;      } return $input; }
	sub trim_end     { my ($class, $input) = @_; if($input){ $input =~ s/\s+$//g;      } return $input; }

	sub get_option { my ($class, $key) = @_; return $OPTIONS->{$key} if defined $OPTIONS->{$key}; return undef; }
	sub set_option { my ($class, $key, $value) = @_; if(defined $OPTIONS->{$key}){ $OPTIONS->{$key} = $value; } }
	sub list_options
	{[
		{ opt => ["--clear | -c"], desc => ["Clears screen before command execution."] },
		{ opt => ["--env name:value | --env=name:value | -E name:value"], desc => ["Set environment variable for execution context. Could be used multiple times."] },
		{ opt => ["--help | -h"], desc => ["Print this usage guide (ignores `-q` option)"] },
		{ opt => ["--quiet | -q"], desc => ["Turn quiet mode on (don't show messages)"] },
		{ opt => ["--var name:value | --var=name:value | -V name:value"], desc => ["Change value of a variable. Could be used multiple times."] },
		{ opt => ["--version | -v"], desc => ["Print title box, or version number only (if quiet mode enabled)"] },
	]}
	sub parse_options
	{
		my ($class) = @_;
		my $error_msg = "";
		open my $error_fh, '>', \$error_msg or $class->print_msg("ERROR", "Cannot open scalar: $!", THEN_DIE);
		local *STDERR = $error_fh;
		Getopt::Long::Configure("gnu_getopt");
		my $successful = GetOptions(
			"sub-command" => \$OPTIONS->{subcmd},
			"clear|c"     => \$OPTIONS->{clear},
			"quiet|q"     => \$OPTIONS->{quiet},
			"help|h"      => \$OPTIONS->{help},
			"version|v"   => \$OPTIONS->{version},
			"env|E=s@"    => sub { if($_[1] =~ m/^(\w+)\s*:\s*(.+)$/){ my ($k, $v) = ($1, $2); $OPTIONS->{envs}->set($k, $v); } },
			"var|V=s@"    => sub { if($_[1] =~ m/^\$?([\w\-]+)\s*:\s*(.+)$/){ my ($k, $v) = ($1, $2); $OPTIONS->{vars}->set($k, $v); } },
		);
		$OPTIONS->{alias} = (@ARGV > 0 ? $ARGV[0] : undef);
		$OPTIONS->{opts}->push(@ARGV[1..$#ARGV]);
		chomp $error_msg;
		return $error_msg;
	}


	sub print
	{
		my ($class, $color, $msg) = @_;
		print $color, $msg, RESET, "\n" unless $class->get_option("quiet");
	}


	sub print_msg
	{
		my ($class, $type, $msg, $then) = @_;
		if($class->get_option("quiet")){
			exit 1 if defined $then && $then == THEN_DIE;
			exit 0 if defined $then && $then == THEN_EXIT;
			return;
		}
		my $color = BRIGHT_WHITE;
		my $icon = "";
		if($type =~ /^err(?:or)?$/i){ $color = BRIGHT_RED; $icon = "⛔ "; }
		elsif($type =~ /^warn(?:ing)?$/i){ $color = BRIGHT_YELLOW; $icon = "⚠️  "; }
		elsif($type =~ /^info$/i){ $color = BRIGHT_BLUE; $icon = "🔷 "; }
		die $color . $icon . "[$type] $msg" . RESET . "\n" if defined $then && $then == THEN_DIE;
		print $color . $icon . "[$type] $msg" . RESET . "\n";
		exit 0 if defined $then && $then == THEN_EXIT;
	}


	sub switch
	{
		my ($class, $value, $cases) = @_;
		if($class->is_array_ref($cases)){
			for(@$cases){
				next unless $class->is_hash_ref($_);
				next unless defined($_->{is}) && defined($_->{set});
				if($class->is_code_ref($_->{is})){ next unless $_->{is}->($value); }
				elsif($class->is_regexp($_->{is})){ next unless $value =~ $_->{is}; }
				else{ next if $value ne $_->{is}; }
				return $_->{set}->($value) if $class->is_code_ref($_->{set});
				return $_->{set};
			}
			my $default = List::Util::first { $class->is_hash_ref($_) && defined($_->{default}); } @$cases;
			if(defined $default){
				return $default->{default}->($value) if $class->is_code_ref($default->{default});
				return $default->{default};
			}
			return undef;
		}
		$class->print_msg("ERROR", "Utils->switch(): Cases should passed as an array reference of hash references.", THEN_DIE);
	}


	sub os_switch
	{
		my ($class, $cases) = @_;
		my $os = Utils->switch($^O, [
			{ is => "MSWin32", set => ON_WINDOWS },
			{ is => "linux",   set => ON_LINUX },
			{ is => "darwin",  set => ON_MAC },
			{ default => ON_UNKNOWN },
		]);
		my $arms = [];
		for my $k (keys %$cases){ push(@$arms, { is => $k, set => $cases->{$k} }); }
		return $class->switch($os, $arms);
	}


	sub print_title
	{
		my ($class) = @_;
		return if $class->get_option("quiet");
		if($class->get_option("subcmd")){ print "\n"; return; }
		my $lines = [
			[
				{ color => BRIGHT_CYAN . BOLD,    text => APP_DEV  },
				{ color => BRIGHT_YELLOW . BOLD,  text => APP_NAME },
				{ color => BRIGHT_MAGENTA . BOLD, text => "v" . APP_VER  },
			],
			[
				{ color => GREEN, text => "OS:  " },
				{ color => GREEN, text => $class->os_switch({ ON_WINDOWS() => "Windows", ON_LINUX() => "Linux", ON_MAC() => "MacOS", ON_UNKNOWN() => "Unknown" }) },
			],
			[
				{ color => BRIGHT_BLUE, text => "Perl:" },
				{ color => BRIGHT_BLUE, text => $^V },
			],
		];
		my $max_width = 0;
		for my $line (@$lines){
			my $line_text = "";
			for my $part (@$line){ $line_text .= " " . $part->{text}; }
			$line_text = $class->trim_start($line_text);
			unshift(@$line, { width => length($line_text) }); # Meta data of line [0]
			$max_width = $line->[0]->{width} if $line->[0]->{width} > $max_width;
		}
		print BRIGHT_WHITE, "┌", "─" x ($max_width + 2), "┐", RESET, "\n";
		for my $line (@$lines){
			my $line_text = BRIGHT_WHITE . "│ ";
			for my $part (@$line){
				next unless defined $part->{text};
				my $color = (defined $part->{color} ? $part->{color} : "");
				$line_text .= $color . $part->{text} . " ";
			}
			$line_text = $class->trim_end($line_text);
			$line_text .= BRIGHT_WHITE . " " x ($max_width - $line->[0]->{width}) . " │" . RESET . "\n";
			print $line_text;
		}
		print BRIGHT_WHITE, "└", "─" x ($max_width + 2), "┘", RESET, "\n";
	}


	sub get_variable
	{
		my ($class, $path, $variables) = @_;
		my $value = $variables;
		pos($path) = 0;
		while($path =~ /\G([a-z](?:[a-z0-9_-]*[a-z0-9])?|\d+)|\G\[([^\]]+)\]/gic){
			my $key = defined $1 ? $1 : $2;
			if($class->is_hash_ref($value)){
				return undef unless exists $value->{$key};
				$value = $value->{$key};
			}elsif($class->is_array_ref($value)){
				return undef unless $key =~ /^\d+$/ && $key < @$value;
				$value = $value->[$key];
			}else{
				return undef;
			}
		}
		return undef if pos($path) != length($path);
		return $value;
	}


	sub bash
	{
		my ($class, $cmd) = @_;
		return -1 unless defined $cmd;
		if($class->is_array_ref($cmd)){ return system(@$cmd); }
		return system($cmd);
	}


	sub split_commands
	{
		my ($class, $str) = @_;
		my @parts;
		my ($cur, $quote, $escape) = ("", "", 0);
		for my $ch (split(//, $str)){
			if($escape){ $cur .= $ch; $escape = 0; next; }
			if($ch eq "\\"){ $cur .= $ch; $escape = 1; next; }
			if($quote){ $cur .= $ch; $quote = "" if $ch eq $quote; next; }
			if($ch eq "'" || $ch eq '"'){ $cur .= $ch; $quote = $ch; next; }
			if ($ch eq ";"){ push(@parts, $class->trim($cur)) if $cur =~ /\S/; $cur = ""; next; }
			$cur .= $ch;
		}
		push(@parts, $class->trim($cur)) if $cur =~ /\S/;
		return @parts;
	}


	sub open_browser
	{
		my ($class, $url) = @_;
		my $cmd = $class->os_switch({
			ON_WINDOWS() => "cmd /c start \"\" $url",
			ON_LINUX()   => "xdg-open $url",
			ON_MAC()     => "open \"$url\"",
		});
		if($cmd){
			$class->print(BRIGHT_CYAN, "⛓ OPEN BROWSER: $url");
			$class->bash($cmd);
		}else{
			$class->print_msg("ERROR", "Could not open default browser for $url", THEN_DIE);
		}
	}


################################################################################


	package InternalCommands;

	use strict;
	use warnings;

	use List::Util qw( first );
	use Term::ANSIColor qw(:constants);

	our $METHODS_LIST = HashMap->from([
		{ dev      => "Development playground of H8 Launcher" },
		{ clear    => "Clear terminal" },
		{ dump     => "Dump parsed commands" },
		{ edit     => "Open \"~/.launcher-commands.yaml\" file in TEXT_EDITOR" },
		{ env      => "Dump environment variables available in Launcher context" },
		{ fullname => "Prints `full name` of current logged in user" },
		{ repo     => "Opens GitHub repository of project by default Browser" },
		{ title    => "Draw title box in output" },
		{ username => "Prints `username` of current logged in user" },
		{ vars     => "Dump parsed variables" },
	]);

	sub new
	{
		my ($class, $commands, $variables) = @_;
		for(@{ main::DISABLED_INTERNAL_COMMANDS() }){ $METHODS_LIST->delete($_); }
		bless { user_commands => $commands, user_variables => $variables }, $class;
	}

	sub _keys { my ($self) = @_; return $METHODS_LIST->keys(); }
	sub _has  { my ($self, $key) = @_; $key =~ s/^@//; return $METHODS_LIST->has($key); }
	sub _desc { my ($self, $key) = @_; $key =~ s/^@//; my $item = $METHODS_LIST->get($key); return $item || ""; }
	sub _call {
		my ($self, $key) = @_;
		$key =~ s/^@//;
		Utils->print_msg("ERROR", "Internal command \"\@$key\" is not available.", Utils::THEN_DIE()) unless $METHODS_LIST->has($key);
		$self->$key() if $self->can($key);
	}

	sub dev
	{
		print "Launcher Dev Playground\n";
	}

	sub clear
	{
		Utils->bash('clear');
	}

	sub dump
	{
		my ($self) = @_;
		Utils->dump($self->{user_commands});
	}

	sub edit
	{
		my $file = main::COMMANDS_FILE();
		my $cmd = main::TEXT_EDITOR() =~ s/\{file\}/$file/r;
		Utils->print_msg("INFO", "Editing \"$file\" file...") unless Utils->get_option("quiet");
		Utils->bash($cmd);
	}

	sub env
	{
		my $opts = Utils->get_option("opts");
		if($opts->length() > 0){
			my $no_keys = $opts->includes("/no-keys") and $opts->delete("/no-keys");
			$opts->for_each(sub {
				my $k = uc($_[0]);
				if(defined $ENV{$k}){
					print $k, "=" unless $no_keys;
					print $ENV{$k}, "\n";
				}
			});
		}else{
			for my $k (keys %ENV){
				print BRIGHT_BLUE, $k, BRIGHT_MAGENTA, " = ", RESET, $ENV{$k}, RESET, "\n";
			}
		}
	}

	sub fullname
	{
		print Utils->os_switch({
			Utils::ON_WINDOWS() => sub { Win32::GetFullUserName() || Win32::LoginName() },
			Utils::ON_LINUX()   => sub { my $n = (getpwuid($<))[6]; $n =~ s/,.*$//; $n },
			Utils::ON_MAC()     => sub { my $n = (getpwuid($<))[6]; $n =~ s/,.*$//; $n },
		}), "\n";
	}

	sub repo
	{
		Utils->open_browser(Utils::APP_REPO());
	}

	sub title
	{
		Utils->print_title();
	}

	sub username
	{
		print $ENV{USER} || $ENV{USERNAME} || $ENV{LOGNAME}, "\n";
	}

	sub vars
	{
		my ($self) = @_;
		Utils->dump($self->{user_variables});
	}


################################################################################


	package HashMap;

	use strict;
	use warnings;

	# Static method used to create a HashMap instance directly from input "array of arrays" or "array of hashes":
	# - Array Of Arrays --> Inner arrays should have only 2 items: [ key, value ]
	# - Array Of Hashes --> Inner hashes should have only 1 item:  { key => value }
	sub from
	{
		my ($class, $items) = @_;
		my $map = $class->new();
		if(Utils->is_array_ref($items)){
			for my $item (@$items){
				if(Utils->is_array_ref($item) && @$item == 2){
					$map->set($item->[0] => $item->[1]);
				}elsif(Utils->is_hash_ref($item) && CORE::keys %$item == 1){
					$map->set((CORE::keys %$item)[0], $item->{(CORE::keys %$item)[0]});
				}
			}
		}
		return $map;
	}

	# Creates new instance:
	sub new { my ($class) = @_; bless { keys => [], data => {} }, $class; }

	# Returns number of items in map:
	sub length { my ($self) = @_; scalar(@{ $self->{keys} }); }

	# Checks wether the `$key` exists in map:
	sub has { my ($self, $key) = @_; return CORE::exists($self->{data}->{$key}); }

	# Add `$key` if not exists, or update it with `$value`:
	sub set { my ($self, $key, $value) = @_; if(!$self->has($key)){ CORE::push(@{ $self->{keys} }, $key); } $self->{data}->{$key} = $value; }

	# Only add `$key` if not exists:
	sub put { my ($self, $key, $value) = @_; if(!$self->has($key)){ CORE::push(@{ $self->{keys} }, $key); $self->{data}->{$key} = $value; } }

	# Returns value of `$key`:
	sub get { my ($self, $key) = @_; return $self->{data}->{$key}; }

	# Get list of keys:
	sub keys { my ($self) = @_; return @{ $self->{keys} }; }

	# Get list of values:
	sub values { my ($self) = @_; return CORE::map { $self->{data}->{$_} } @{ $self->{keys} }; }

	# Get index of `$key` in map:
	sub index_of { my ($self, $key) = @_; for(my $i = 0; $i < @{ $self->{keys} }; $i++){ return $i if $self->{keys}->[$i] eq $key; } return -1; }

	# Makes a clone of map:
	sub clone { my ($self) = @_; my $cloned = HashMap->new(); $self->for_each(sub { my ($v, $k) = @_; $cloned->set($k => $v); }); return $cloned; }

	# Returns the item (key, value) at specified `$index`:
	sub at
	{
		my ($self, $index) = @_;
		return undef if !defined $index;
		return undef if $index < 0 || $index > @{ $self->{keys} };
		my $key = $self->{keys}->[$index];
		return ($key, $self->{data}->{$key});
	}

	# Deletes the item with specified `$key`:
	sub delete
	{
		my ($self, $key) = @_;
		return unless $self->has($key);
		CORE::delete $self->{data}->{$key};
		@{ $self->{keys} } = CORE::grep { $_ ne $key } @{ $self->{keys} };
	}

	# Calls provided `$callback` for each item of map:
	sub for_each
	{
		my ($self, $callback) = @_;
		if(Utils->is_code_ref($callback)){
			while(my ($i, $k) = CORE::each @{ $self->{keys} }){ my $v = $self->{data}->{$k}; $callback->($v, $k, $i, $self); }
		}
	}

	# Returns first item of map that provided `$callback` returns TRUE for it:
	sub find
	{
		my ($self, $callback) = @_;
		if(Utils->is_code_ref($callback)){
			while(my ($i, $k) = CORE::each @{ $self->{keys} }){ my $v = $self->{data}->{$k}; return $v if $callback->($v, $k, $i, $self); }
		}
	}

	# Filters items of map using provided `$callback` and returns a new HashMap:
	sub filter
	{
		my ($self, $callback) = @_;
		if(Utils->is_code_ref($callback)){
			my $result = HashMap->new();
			while(my ($i, $k) = CORE::each @{ $self->{keys} }){ my $v = $self->{data}->{$k}; $result->set($k, $v) if $callback->($v, $k, $i, $self); }
			return $result;
		}
	}

	# Calls provided `$callback` on each item and change its value, returned in new HashMap:
	sub map
	{
		my ($self, $callback) = @_;
		if(Utils->is_code_ref($callback)){
			my $result = HashMap->new();
			while(my ($i, $k) = CORE::each @{ $self->{keys} }){ my $v = $self->{data}->{$k}; $result->set($k, $callback->($v, $k, $i, $self)); }
			return $result;
		}
	}

	# Generates a hashref of items:
	sub to_hash
	{
		my ($self) = @_;
		my $result = {};
		for(CORE::keys %{ $self->{data} }){ $result->{$_} = $self->{data}->{$_}; }
		return $result;
	}


################################################################################


	package Array;

	use strict;
	use warnings;

	use List::Util qw( first );

	# Static method used to create an Array instance directly from input "arrayref":
	sub from
	{
		my ($class, $items) = @_;
		my $array = $class->new();
		if(Utils->is_array_ref($items)){
			for my $item (@$items){ $array->push($item); }
		}
		return $array;
	}

	# Creates new instance:
	sub new { my ($class) = @_; bless { items => [] }, $class; }

	# Returns number of items in array:
	sub length { my ($self) = @_; scalar(@{ $self->{items} }); }

	# Returns index of item equals to `$value`:
	sub index_of { my ($self, $value) = @_; for(my $i = 0; $i < @{ $self->{items} }; $i++){ return $i if $self->{items}->[$i] eq $value; } return -1; }

	# Returns index of last item equals to `$value`:
	sub last_index_of { my ($self, $value) = @_; for(my $i = @{ $self->{items} } - 1; $i >= 0; $i--){ return $i if $self->{items}->[$i] eq $value; } return -1; }

	# Checks wether array has specified `$value` or not:
	sub includes { my ($self, $value) = @_; for(my $i = 0; $i < @{ $self->{items} }; $i++){ return Utils::TRUE() if $self->{items}->[$i] eq $value; } return Utils::FALSE(); }

	# Add one or more elements to the end of array:
	sub push { my ($self, @values) = @_; return CORE::push(@{ $self->{items} }, @values); }

	# Add one or more elements to the end of array if did not exist:
	sub unique_push { my ($self, @values) = @_; for(@values){ CORE::push(@{ $self->{items} }, $_) unless $self->includes($_); } return $self->length(); }

	# Add one or more elements to the beginning of array:
	sub unshift { my ($self, @values) = @_; return CORE::unshift(@{ $self->{items} }, @values); }

	# Add one or more elements to the beginning of array:
	sub unique_unshift { my ($self, @values) = @_; for(reverse @values){ CORE::unshift(@{ $self->{items} }, $_) unless $self->includes($_); } return $self->length(); }

	# Removes and returns the last element of array:
	sub pop { my ($self) = @_; return CORE::pop(@{ $self->{items} }); }

	# Removes and returns the first element of array:
	sub shift { my ($self) = @_; return CORE::shift(@{ $self->{items} }); }

	# Removes the elements designated by `$offset` and `$length` from array, and replaces them with provided `@new_items`:
	sub splice { my ($self, $offset, $length, @new_items) = @_; return CORE::splice(@{ $self->{items} }, $offset, $length, @new_items); }

	# Deletes an item of array by specified `$value`:
	sub delete { my ($self, $value) = @_; my $pos = $self->index_of($value); if($pos >= 0){ $self->splice($pos, 1); return Utils::TRUE(); } return Utils::FALSE(); }

	# Joins the separate string items into a single string with fields separated by `$sep`:
	sub join { my ($self, $sep) = @_; CORE::join($sep, @{ $self->{items} }); }

	# Makes a clone of array:
	sub clone { my ($self) = @_; return $self->map(sub { my ($v) = @_; return $v; }); }

	# Returns the item at specified `$index` (supports negative index):
	sub at
	{
		my ($self, $index) = @_;
		$index = $self->length() + $index if $index < 0;
		return undef if $index >= $self->length();
		return $self->{items}->[$index];
	}

	# Calls provided `$callback` for each item of array:
	sub for_each {
		my ($self, $callback) = @_;
		if(Utils->is_code_ref($callback)){
			while(my ($i, $v) = CORE::each @{ $self->{items} }){ $callback->($v, $i, $self); }
		}
	}

	# Returns first item of array that provided `$callback` returns TRUE for it:
	sub find
	{
		my ($self, $callback) = @_;
		if(Utils->is_code_ref($callback)){
			while(my ($i, $v) = CORE::each @{ $self->{items} }){ return $v if $callback->($v, $i, $self); }
		}
	}

	# Filters items of array using provided `$callback` and returns a new Array:
	sub filter
	{
		my ($self, $callback) = @_;
		if(Utils->is_code_ref($callback)){
			my $result = Array->new();
			while(my ($i, $v) = CORE::each @{ $self->{items} }){ $result->push($v) if $callback->($v, $i, $self); }
			return $result;
		}
	}

	# Calls provided `$callback` on each item and use returned value as new value of item:
	sub map
	{
		my ($self, $callback) = @_;
		if(Utils->is_code_ref($callback)){
			my $result = Array->new();
			while(my ($i, $v) = CORE::each @{ $self->{items} }){ $result->push($callback->($v, $i, $self)); }
			return $result;
		}
	}

	# Generates an arrayref of items:
	sub to_array
	{
		my ($self) = @_;
		my $result = [];
		for(@{ $self->{items} }){ CORE::push(@$result, $_); }
		return $result;
	}


################################################################################


	package SimpleYAML;

	use strict;
	use warnings;


	sub parse
	{
		my ($class, $text) = @_;
		my @lines = split(/\n/, $text);
		my ($data, $next) = _parse_block(\@lines, 0, 0);
		return $data;
	}


	sub parse_file
	{
		my ($class, $path) = @_;
		open my $fh, "<", $path or die "open $path: $!";
		local $/;
		return $class->parse(<$fh>);
	}


	sub _parse_block
	{
		my ($lines, $i, $indent) = @_;
		my @items;
		my %map;
		my $mode; # seq | map
		while($i <= $#$lines){
			my $line = $lines->[$i];
			$line =~ s/\r$//;
			if($line =~ /^\s*(?:#.*)?$/){ $i++; next; }
			my ($ind) = $line =~ /^(\s*)/;
			my $cur = length($ind);
			last if $cur < $indent;
			die "Invalid indentation at line " . ($i + 1) if $cur > $indent && !defined $mode;
			$line =~ s/^\s+//;
			$line =~ s/\s+#.*$//;
			if($line =~ /^-\s*(.*)$/){
				$mode = "seq" if !defined $mode;
				die "Mixed YAML types at line " . ($i + 1) if $mode ne "seq";
				my $rest = $1;
				if($rest eq ""){
					my ($child, $ni) = _parse_block($lines, $i + 1, $indent + 2);
					push @items, $child;
					$i = $ni;
					next;
				}
				if($rest =~ /^([^:]+):\s*(.*)$/){
					my ($k, $v) = ($1, $2);
					$k =~ s/\s+$//;
					my %obj;
					if($v =~ /^(\||>)(?:\s+.*)?$/){
						my ($scalar, $ni) = _parse_block_scalar($lines, $i + 1, $indent + 2, $1);
						$obj{$k} = $scalar;
						$i = $ni;
					}elsif($v eq ""){
						my ($child, $ni) = _parse_block($lines, $i + 1, $indent + 2);
						$obj{$k} = $child;
						$i = $ni;
					}else{
						$obj{$k} = _parse_scalar($v);
						$i++;
					}
					push @items, \%obj;
					next;
				}
				push @items, _parse_scalar($rest);
				$i++;
				next;
			}
			if($line =~ /^([^:]+):\s*(.*)$/){
				$mode = "map" if !defined $mode;
				die "Mixed YAML types at line " . ($i + 1) if $mode ne "map";
				my ($k, $v) = ($1, $2);
				$k =~ s/\s+$//;
				if ($v =~ /^(\||>)(?:\s+.*)?$/) {
					my ($scalar, $ni) = _parse_block_scalar($lines, $i + 1, $indent + 2, $1);
					$map{$k} = $scalar;
					$i = $ni;
					next;
				}
				if ($v eq "") {
					my ($child, $ni) = _parse_block($lines, $i + 1, $indent + 2);
					$map{$k} = $child;
					$i = $ni;
					next;
				}
				$map{$k} = _parse_scalar($v);
				$i++;
				next;
			}
			die "Cannot parse line " . ($i + 1) . ": $line";
		}
		return defined $mode && $mode eq "seq" ? (\@items, $i) : (\%map, $i);
	}


	sub _parse_block_scalar
	{
		my ($lines, $i, $indent, $style) = @_;
		my @buf;
		while($i <= $#$lines){
			my $line = $lines->[$i];
			$line =~ s/\r$//;
			my ($ind) = $line =~ /^(\s*)/;
			my $cur = length($ind);
			last if $line =~ /^\s*(?:#.*)?$/ && $cur < $indent;
			last if $cur < $indent;
			if($line =~ /^\s*$/){
				push @buf, "";
				$i++;
				next;
			}
			die "Invalid block scalar indentation at line " . ($i + 1) if $cur < $indent;
			$line =~ s/^\Q$ind\E//;
			push @buf, $line;
			$i++;
		}
		my $text = join "\n", @buf;
		if ($style eq "|") {
			return ($text . "\n", $i);
		}
		$text =~ s/\n+/ /g;
		$text =~ s/^\s+|\s+$//g;
		return ($text, $i);
	}


	sub _parse_scalar
	{
		my ($v) = @_;
		return undef if !defined $v || $v eq "" || $v eq "~" || lc($v) eq "null";
		return 1 if lc($v) eq "true";
		return 0 if lc($v) eq "false";
		if($v =~ /^"(.*)"$/s){
			my $s = $1;
			$s =~ s/\\n/\n/g;
			$s =~ s/\\"/"/g;
			$s =~ s/\\\\/\\/g;
			return $s;
		}
		if($v =~ /^'(.*)'$/s){
			my $s = $1;
			$s =~ s/''/'/g;
			return $s;
		}
		return $v + 0 if $v =~ /^-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?$/;
		return $v;
	}


################################################################################

	package main; # Return to "main" package (above BEGIN{} block)

}
