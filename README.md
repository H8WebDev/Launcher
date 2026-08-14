# H8 Launcher

__H8 Launcher__ is a lightweight Perl-based command launcher that lets you define and run custom shell commands using simple aliases configured in a YAML file. It supports custom variables, command descriptions, and execution context options, providing a convenient way to organize and quickly access frequently used terminal commands.


## Compatibility

H8 Launcher is designed to run on:
- Linux
- Windows

It requires Perl to be installed and available in your system `PATH`.


## Features

- __Command Aliases__ — Define custom shell commands and run them with short, memorable aliases.
- __YAML Configuration__ — Manage your commands and settings in a simple YAML file.
- __Custom Variables__ — Define reusable variables and use them in your commands.
- __Command Descriptions__ — Add descriptions that are displayed in the usage screen.
- __Execution Metadata__ — Customize the execution context of individual commands.
- __Zero-configuration Setup__ — Automatically creates the configuration file (`~/.launcher-commands.yaml`) on first run.
- __Fast Command Execution__ — Run any configured command directly with `run <alias>`.


## Requirements

- Perl 5.x
- No external Perl modules are required.


## Installation

__H8 Launcher__ requires [Perl](https://www.perl.org/) to be installed and available in your system `PATH`.

### Linux / Unix

#### 1. Clone The Repository
```sh
git clone https://github.com/H8WebDev/Launcher.git
cd Launcher
```
Alternatively, you can download the repository as a ZIP file and extract it.

#### 2. Run The Installation Script:
```sh
chmod a+x install.sh
./install.sh
```
The installer will:
- Checks that Perl is installed.
- Makes the `run` script executable.
- Creates `~/.local/bin` if it does not exist.
- Creates a symbolic link from `~/.local/bin/run` to the __H8 Launcher__ `run` script.
- Checks whether `~/.local/bin` is available in your `PATH`.

After installation, restart your terminal if necessary and run:
```sh
run
```
You should see the usage screen.

### Windows

#### 1. Clone The Repository
```sh
git clone https://github.com/H8WebDev/Launcher.git
cd Launcher
```
Alternatively, download the repository as a ZIP file and extract it.

#### 2. Run The __PowerShell__ Installation Script:
```sh
.\install.ps1
```

The installer will:
- Checks that Perl is installed.
- Adds the __H8 Launcher__ directory to your user `PATH`.
- Makes the `run.cmd` wrapper available as the `run` command.

After installation, __restart your terminal__ so that the updated `PATH` takes effect.

You can then run __H8 Launcher__ from any directory:
```sh
run
```

> Note: Perl must be installed and available in your system `PATH` on both __Linux__ and __Windows__.


## Usage

After installation, run __H8 Launcher__ from any directory:
```sh
run
```

On the first run, __H8 Launcher__ creates a configuration file in your home directory:
```
~/.launcher-commands.yaml
```

It then displays the usage screen with the available command aliases.

### Edit The Configuration

Commands are defined as aliases in `~/.launcher-commands.yaml`.

__H8 Launcher__ provides the `@edit` command to quickly open the configuration file with `nano` (as default editor):
```sh
run @edit
```
This opens `~/.launcher-commands.yaml` with `nano`.
You can use this command whenever you want to add, modify, or remove commands.

### Define Commands

Commands are defined as aliases in `~/.launcher-commands.yaml`:
```yaml
$my-name: World

my-alias:
  cmd: clear; echo "Hello ${my-name}!"
  desc: Say my name!
  meta:
    - quiet
	- clear
```
Each command can contain:
- `cmd` — The shell command to execute.
- `desc` — A description displayed in the usage screen.
- `meta` — Optional metadata used to customize the command's execution context.

You can also define custom variables using the `$<var_name>` syntax and reference them in commands with `${<var_name>}`.

### Run Commands

To execute a configured command, use its alias, example:
```sh
run my-alias
```
__H8 Launcher__ reads the alias from `~/.launcher-commands.yaml` and executes the corresponding command(s).

#### Command Parameters

Aliases can receive positional parameters from the command line. Arguments that are not options (do not start with `-` or `--`), as well as arguments appearing after `--`, are passed to the alias as positional parameters.

These parameters can be accessed inside `cmd` using `$0`, `$1`, `$2`, and so on.
- `$0` — Contains all positional arguments as a single value.
- `$1` — Contains the first positional argument.
- `$2` — Contains the second positional argument.
- And so on.

For example:
```yaml
say-hello:
  cmd: echo "Hello $1"
  desc: Say hello to someone
```
Run the command with:
```sh
run say-hello Alice
```
Output:
```
Hello Alice
```

You can use `$0` when you want to access all positional arguments as a single value:
```yaml
say-hello:
  cmd: echo "Hello $0"
```
Run it:
```sh
run say-hello John Junior Doe
```
Output:
```
Hello John Junior Doe
```

Individual positional arguments can also be combined:
```yaml
greet:
  cmd: echo "Hello $1 $2"
```
Run:
```sh
run greet John Doe The 2nd
```
Output:
```
Hello John Doe
```

Arguments following `--` are also treated as positional parameters:
```sh
run say-hello -- John Junior Doe
```
Output:
```
Hello John Junior Doe
```

### View Available Commands
Run __H8 Launcher__ without an alias to display the usage screen and see the available commands:
```sh
run
```


## License

MIT
