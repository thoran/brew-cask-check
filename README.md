# brew-cask-check

Run Homebrew's checks upon an edited cask in a clone of Homebrew/homebrew-cask, before opening a pull request, where homebrew/cask isn't tapped.

## Installation

### 0. Have a recent version of Ruby installed, with the switches.rb gem

```shell
gem install switches.rb
```

### 1. Manually

```shell
git clone https://github.com/thoran/brew-cask-check
cp ./brew-cask-check/bin/brew-cask-check to your preferred executable path
chmod +x /path/to/brew-cask-check
```

Being on the path as `brew-cask-check`, it is also `brew cask-check`.

## Usage

From the clone, upon the edited cask:

```shell
brew cask-check Casks/t/tiger-trade.rb
```

It runs `brew style` and `brew audit --online` upon it, reports each, and exits 1 where either failed.

To install and uninstall it as well:

```shell
brew cask-check -i Casks/t/tiger-trade.rb
```

Where the cask was installed beforehand, it is reinstalled from the edited cask, uninstalled, and the official one installed again. Where it wasn't, it is installed and uninstalled, and nothing is put back.

| Option | Takes | What it does |
| --- | --- | --- |
| `-i`, `--install` | — | Install and uninstall it as well |
| `-n`, `--new` | — | Audit it as a cask new to Homebrew/homebrew-cask, with `--new` |
| `-t`, `--tap-name` | user/repository | The tap it is checked in, `<user>/cask-check` by default |
| `--version` | — | Show the version |
| `-h`, `--help` | — | Show the help |

## Why it's wanted

Homebrew asks for `brew style`, `brew audit --cask --online`, and an install and uninstall before a pull request to Homebrew/homebrew-cask. brew checks only casks which are in a tap, and since brew installs casks from the API, homebrew/cask is mostly not tapped, so a cask in a clone is in no tap. Neither can brew be pointed at the file: given a path, `brew style --cask` takes it for a name, and exits 1 without saying why.

## How it works

1. `brew tap-new <user>/cask-check --no-git`, and the cask copied into its `Casks/<first letter>/`.
2. `brew style --cask <user>/cask-check/<token>`.
3. `brew trust --cask` it, brew loading no cask from an untrusted tap, then `brew audit --cask --online` it.
4. With `--install`, `brew reinstall --cask` it, or `install` where it wasn't installed, then `brew uninstall --cask` it, then `brew install --cask homebrew/cask/<token>` where it was installed beforehand.
5. Whether or not anything failed, or it was interrupted: trust the cask again, since `brew untap` loads the casks in a tap and refuses an untrusted one; `brew untap`; and undo any trust brew's trusted entries didn't have beforehand.

## Assumptions

- The tap it checks in doesn't exist yet. Where it does, it stops, rather than check in a tap and then remove one which held something else.
- brew is run with `HOMEBREW_NO_AUTO_UPDATE=1`, and otherwise in the environment it is given, so as `HOMEBREW_CASK_OPTS` holds for the install: an `--appdir` given there is where the app goes.
- The cask file is named for its token, as in Homebrew/homebrew-cask.

## Tests

```shell
ruby test/brew-cask-check_test.rb
```

They run it against a fake brew, and touch neither Homebrew nor any app.

## Contributing

1. Fork it: `https://github.com/thoran/brew-cask-check/fork`
2. Create your feature branch: `git checkout -b my-new-feature`
3. Commit your changes: `git commit -am 'Add some feature'`
4. Push to the branch: `git push origin my-new-feature`
5. Create a new pull request


## License

MIT
