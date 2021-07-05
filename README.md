# REPLica

[![ci](https://github.com/ReplicaTest/REPLica/actions/workflows/ci.yml/badge.svg)](https://github.com/ReplicaTest/REPLica/actions/workflows/ci.yml)

Golden tests for Command Line interfaces.

## Table of Content

* [Purpose](#purpose)
    * [Why REPLica](#why-replica)
    * [Features](#features)
* [Install](#install)
    * [Requirements](#requirements)
    * [Steps](#steps)
* [Quickstart](#quickstart)
    * [JSON](#json)
    * [dhall](#dhall)
* [Writing tests](#writing-tests)
    * [`command`](#command)
    * [`beforeTest` and `afterTest`](#beforetest-and-aftertest)
    * [`require`](#require)
    * [`input`](#input)
    * [`tags`](#tags)
    * [`description`](#description)
    * [`pending`](#description)
    * [`status`](#status)
    * [`spaceSensitive`](#spacesensitive)
    * [`stdOut` and `stdErr`](#stdout-and-stderr)
    * [`files`](#files)
* [Expectations](#expectations)
    * [Golden value](#golden-value)
    * [Exact value](#exact-value)
    * [Contains](#contains)
    * [Complex expectations](#complex-expectations)
* [Going further](#going-further)
    * [REPLica in my project?](#replica-in-my-project)
* [Roadmap](#roadmap)
* [Help and support](#help-and-support)

## Purpose

Replica aims at managing tests suites composed of command line interfaces calls.

It compares the output of the command line to a "golden value": a stored value of the expected
outcome of the command line call.
If you want a more detailed introduction to golden testing, here is a [nice introduction][golden].

The idea comes from the way tests are implemented in [idris2][idris tests].

Its approach is similar to the one proposed by CI/CD tools like [github actions][] or [gitlab ci][]:
a tests suite is described in a json (or more preferably [dhall][]) file that is processed by the
tool to generate tests.

### Why REPLica?

There are few frameworks that are dedicated to CLI tests.
None of them, to my knowledge, mix of a structured document to document the test
and of interactive golden value generation to specify the expectation.

This approach ease the modification of the CLI output in the early development phases and
provide a clear syntax for test development and maintenance.

Other CLI testing frameworks

- [Idris2 test package][idris tests]: REPLica's daddy. REPLica was created with the idea to provide
  a more structured way to write tests (the JSON/Dhall specification) and to develop the
  functionalities (see the [features])
- [Pester](https://github.com/pester/Pester): By far more mature than REPLica, thought for
  powershell, it includes test coverage, test discovery, complex expectations DSL and so on.
  Pester doesn't, however, provides a way to generate expectation from previous run.
- [shelltestrunner](https://hackage.haskell.org/package/shelltestrunner): another minimal tool to
  test CLI, but without golden value generation or test tags.

### Features

- Test tags
- Test dependencies (test are run only if other tests succeed)
- Check exit status
- Multi-threads
- Run only selected tests/tags
- Expectation language
- Can test standard output, standard error and file content

## Install

### Requirements

- [idris2](https://idris-lang.org) (v0.4.0);
- [git](https://git-scm.com);
- while you can go with it and use JSON, we recommand to use [dhall][] and [dhall-to-json][].

### Steps

```shell
# clone repo
git clone git@github.com:ReplicaTest/REPLica.git

# install replica
make instal

# Ensure that `${HOME}/.local/bin` is in your path

# health-check
replica help
```

## Quickstart

### JSON

```shell
replica new hello.json
```

This command creates a `hello.json` file that contains a sample test:

```
$ replica new hello.json
Test file created (JSON): hello.json

$ cat hello.json
{
  "hello": {
    "command": "echo \"Hello, World!\"",
    "description": "This test is a placeholder, you can edit it.",
    "spaceSensitive": false,
    "status": true,
    "stdOut": {
      "generated": false,
      "consecutive": [
        "Hello",
        "World"
      ],
      "end": "!"
    }
  }
}
```

The given test checks that the output of `echo "Hello, World!"` contains consecutively
`Hello` and "World", and ends with an exclamation mark (`'!'`).

You can directly run replica on it: `replica run hello.json`.
You should obtain the following result:


```
$ replica run hello.json
--------------------------------------------------------------------------------
Running tests...
  ✅  hello
--------------------------------------------------------------------------------
Summary:
  ✅  (Success): 1 / 1
```

Now, edit the `hello.json` file and change the `stdOut` part so that your file looks
like this:

```json
{
  "hello": {
    "command": "echo \"Hello, World!\"",
    "description": "This test is a placeholder, you can edit it.",
    "spaceSensitive": false,
    "status": true,
    "stdOut": true
  }
}
```

Instead of providing an expectation, we now rely on a golden value:
a previously saved value of the output of the tested command.
Unfortunately, we didn't save any yet... and thus `replica run hello.json`
fails now:

```
$ replica run hello.json
--------------------------------------------------------------------------------
Running tests...
  ❌  hello:
      [Missing Golden for standard output]
      [Unexpected content for standard output]
      Error on standard output:
      Given:
        Hello, World!

--------------------------------------------------------------------------------
Summary:
  ❌  (Failure): 1 / 1
```

It's totally fine: `replica` has no golden value for this test yet, we need to build one.
To do so, we will rerun the test in the interactive mode: `replica run --interactive hello.json`.
Now you should be prompted if you want to set the golden value for the test:

```
$ replica run --interactive hello.json
--------------------------------------------------------------------------------
Running tests...
hello: Golden value mismatch for standard output
Expected: Nothing Found
Given:
Hello, World!

Do you want to set the golden value? [N/y]
```

Answer `y` (or `yes`) and the test should pass.
Now that the golden value is set, we can retry to run the suite in a non interactive mode:
`replica run hello.json`...

```
$ replica run hello.json
--------------------------------------------------------------------------------
Running tests...
  ✅  hello
--------------------------------------------------------------------------------
Summary:
  ✅  (Success): 1 / 1
```


TADA... it works.

If you want to see it fails again, you can modify the command in `hello.json`.

### Dhall

```shell
replica new hello.dhall
```

This command creates a `hello.dhall` file that contains a sample test:

```
$ replica new hello.dhall
Test file created (Dhall): hello.dhall

$ cat hello.dhall
let Replica = https://raw.githubusercontent.com/ReplicaTest/replica-dhall/main/package.dhall
let Prelude = Replica.Prelude
let Test = Replica.Test
let Status = Replica.Status
let Expectation = Replica.Expectation

let hello = Test.Success ::
   { command = "echo \"Hello, World!\""
   , description = Some "This test is a placeholder, you can edit it."
   , spaceSensitive = False
   , stdOut = Expectation ::
       {consecutive = ["Hello", "World"], end = Some "!"}
   }

let tests : Replica.Type = toMap { hello }

in tests
```

The given test checks that the output of `echo "Hello, World!"` contains consecutively
`Hello` and "World", and ends with an exclamation mark (`'!'`).

At this stage, `replica` isn't able to process `dhall` files directlyr.
We have to generate a JSON file first and then to execute it.


```
$ dhall-to-json --output hello.json --file hello.dhall
$ replica run hello.json
--------------------------------------------------------------------------------
Running tests...
  ✅  hello
--------------------------------------------------------------------------------
Summary:
  ✅  (Success): 1 / 1
```

Now, edit the `hello.dhall` file and change the `stdOut` part so that your file looks
like this:

```dhall
let Replica = https://raw.githubusercontent.com/ReplicaTest/replica-dhall/main/package.dhall
let Prelude = Replica.Prelude
let Test = Replica.Test
let Status = Replica.Status
let Expectation = Replica.Expectation

let hello = Test.Success ::
   { command = "echo \"Hello, World!\""
   , description = Some "This test is a placeholder, you can edit it."
   , spaceSensitive = False
   , stdOut = Replica.Generated True
   }

let tests : Replica.Type = toMap { hello }

in tests
```

Instead of providing an expectation, we now rely on a golden value:
a previously saved value of the output of the tested command.
Unfortunately, we didn't save any yet... and thus **if we recompile**
`hello.json`, `replica run hello.json` fails now:

```
$ dhall-to-json --output hello.json --file hello.dhall
$ replica run hello.json
--------------------------------------------------------------------------------
Running tests...
  ❌  hello:
      [Missing Golden for standard output]
      [Unexpected content for standard output]
      Error on standard output:
      Given:
        Hello, World!

--------------------------------------------------------------------------------
Summary:
  ❌  (Failure): 1 / 1
```

It's totally fine: `replica` has no golden value for this test yet, we need to build one.
To do so, we will rerun the test in the interactive mode: `replica run --interactive hello.json`.
Now you should be prompted if you want to set the golden value for the test:

```
$ replica run --interactive hello.json
--------------------------------------------------------------------------------
Running tests...
hello: Golden value mismatch for standard output
Expected: Nothing Found
Given:
Hello, World!

Do you want to set the golden value? [N/y]
```

Answer `y` (or `yes`) and the test should pass.
Now that the golden value is set, we can retry to run the suite in a non interactive mode:
`replica run hello.json`...

```
$ replica run hello.json
--------------------------------------------------------------------------------
Running tests...
  ✅  hello
--------------------------------------------------------------------------------
Summary:
  ✅  (Success): 1 / 1
```

The main motivation of using dhall is:
- type safety;
- ease to generate a set of similar tests.


## Writing tests

### `command`

The [Quickstart](#quickstart) section introduced a first, minimal test in json:

```json
{ "hello": {"command": "echo \"hello, world!\""} }
```

or in dhall:

```dhall
{ hello = Replica.Minimal::{command = "echo \"Hello, world!\""}}
```

In both case, we have declared the only mandatory field of a test: `command`.

It defines the command that will be tested.
REPLica will save the exit code of the command, the standard output and the standard error.
By default, REPLica will only check the output,
comparing it to the golden value that will be stored in the `interactive` mode.

### `beforeTest` and `afterTest`

The `beforeTest` and `afterTest` allow you to prepare and to clean the test environment.
Warning: commands in each of them run in separated shells.
It means that you can't share (at the moment), variables between `beforeTest`, `command`,
and `afterTest`.
`command` won't be executed if `beforeTest` failed,
and an error will be emited if a command of `beforeTest` or `afterTest` failed.
REPLica distinguish an error (when something went wrong during the execution of a test)
and a failure (when the test doesn't meet the expectations).

```json
{ "test cat":
  { "beforeTest": ["echo \"test\" > foo.txt"]
  , "command": ["cat foo.txt"]
  , "afterTest": ["rm foo.txt"]
}
```

```dhall
{ test_cat = Replica.Minimal::
  { beforeTest = ["echo \"test\" > foo.txt"]
  , command = "cat foo.txt"
  , afterTest = ["rm foo.txt"]
  }
}
```

### `require`

The `require` field ensure that a test will be executed only if the given list of
tests succeed.
If one of the required tests failed, the test will be marked as ignore.

```json
{ "test_first": {"command": "echo \"Hello, \""}
, "test_then":
   { "command":  "echo \"world!\""
   , "require": ["test_first"]
   }
}
```

```dhall
{ test_first = {command = "echo \"Hello, \""}
, test_then =
   { command =  "echo \"world!\""
   , require = ["test_first"]
   }
}
```

### `input`

The `input` field allows you to define inputs for your command, repacing the standard input by it's
content.

```json
{ "send_text_to_cat":
  { "command": "cat"
  , "input" = "hello, wold!"
  }
}
```

```dhall
{ send_text_to_cat = Replica.Minimal::
  { command = "cat"
  , input = "hello, wold!"
  }
}
```
### `tags`

The `tags` field allow you to organise your test suites.
Once you've defined tags for your tests, you can decide to run test that have (or didn't have) a
given tags thanks to REPLica command line options.

```json
{ "hello": {"command": "echo \"hello, world!\""}, "tags": ["example", "hello"]}
```

or in dhall:

```dhall
{ hello = Replica.Minimal::{command = "echo \"Hello, world!\"", tags = ["example", "hello"]}}
```

And then you can run `replica -t example your_file.json` to include tests tagged with `example`
or `replica -T example your_file.json` to exclude them.

### `description`

You can add a `description` to your test.
Description is here for informative purpose and can be displayed with `replica info`.

### `pending`

If `pending` is set to `true`, the corresponding test will be ignored.

### `status``

The `status` field allow you to verify the exit code of your command.
You can either set the value to a boolean,
to check if the command succeeded (`true`) or failed (`false`),
or to a natural, to check if the exit code was exactly the one provided.

```json
{ "success1": {"command": "true", "status": true}
, "success2": {"command": "true", "status": 0}
, "success3": {"command": "false", "status": false}
, "success4": {"command": "false", "status": 1}
, "failure":  {"command": "false", "status": 2}
}
```

The dhall version is slightly more complex, as we need to use a union type to allow booleans and
natural values.
A few helper are available to ease the settings though:

```dhall
{ "success1": Replica.Minimal::{command = "true", status = Replica.Succeed true}
, "success2": Replica.Minimal::{command = "true", status = Replica.Exactly 0}
, "success3": Replica.Minimal::{command = "false", status = Replica.Succeed false}
, "success4": Replica.Minimal::{command = "false", status = Replica.Exactly 1}
, "failure":  Replica.Minimal::{command = "false", status = Replica.Exactly 2}
}
```

### `spaceSensitive`

If this field is set to `false`, all text comparisons that are performed in this test are
space insensitive: it means that the content that the given and expected content are
"normalized" before the comparison: consecutive space-like characters are replaced by a
single space ands consecutive new lines are replaced by a single new line.

### `stdOut` and `stdErr`

By default, REPLica compares the standard output (`stdOut`)
to a (previously generated) golden value,
and ignores totally the output of the standard error (`stdErr`).

The fields `stdOut` and `stdErr` allow you to modify this behaviour.
The possible values for these fields are describe in the [expectations](#expectations)
section.

### `files`

Aside the standard output and error,
REPLica can also check contents of files, as it can be useful to check the result of
a command.
To do so, we can use the `files` field,
which expects an object where keys must be relative paths to the fields to check and
[expectations](#expectations) as a value, to define what is expected for the fields.

## Expectations

For each type of expectations, we give the json and the dhall version.
As we use a union type, dhall version is a bit more verbose, but smart constructors
ease the pain.

### Golden value

The simpliest value for an expectation is a boolean.
`true` means that we compare the content of this source to a golden value,
`false` (or `null`) means that this source is ignored`.

```json
{ "hello": {"command": "echo \"hello, world!\"", "stdOut": false} }
```

or, in dhall:

```dhall
{ hello = Replica.Minimal::{command = "echo \"Hello, world!\"", stdOut = Replica.Generated False}}
```

### Exact value

If you set a string as an expectation, the content of the corresponding source is expected to be
exactly this string.

```json
{ "hello": {"command": "echo \"hello, world!\"", "stdOut": "hello, world!\n"} }
```

or, in dhall:

```dhall
{ hello = Replica.Minimal::{command = "echo \"Hello, world!\"", stdOut = Replica.Exactly "Hello, world!"}}
```

### Contains

If you set a list of strings as a value, the source must contains all the values of the list, in any
order.

```json
{ "hello": {"command": "echo \"hello, world!\"", "stdOut": ["world", "hello"]} }
```

or, in dhall:

```dhall
{ hello = Replica.Minimal::
  {command = "echo \"Hello, world!\"", stdOut = Replica.Contains ["world, hello"]}}
```

### Complex expectations

Complex expectations are a solutions that allows you to compose the solutions given before
and that enables a few other types of expectations.
A complex expectation is an object where the following fields are considered:

- `generated`: true or false, depending on whether you want to use a golden value or not.
- `exact`: if set, the exact expectation for this source.
- `start`: if set, the source must start with this string.
- `end`: if set, the source must end with this string.
- `contains`: a list of string, that must be found in the source.
- `consecutive`: a list of string, that must be found in this order (optionnaly with some text in between) in the source.

```json
{ "hello":
    {"command": "echo \"hello, world!\"",
      "stdOut": { "generated": true
                , "consecutive": ["hello", "world"]
                , "end": "!"
                }
    }
}
```

or, in dhall:

```dhall
{ hello = Replica.Minimal::
  { command = "echo \"Hello, world!\""
  , stdOut = Replica.ComplexExpectation
      { generated = True
      , consecutive = ["hello", "world"]
      , end = Some "!"
      }
  }
}
```

## Going further

REPLica is tested with itelf, you can check the [test file][] to have an overview of the
possibilities.

The [documentation](./documentation) folder also contain useful pieces of information:

- The [tests specification](./documentation/TestSpecification.md) in JSON and Dhall.
- A description of the [tests execution workplan](./documentation/TestExecution.md).

You can also explore the tool options with `replica help`.

### replica in my project?

The [utils](./utils) folder contains a few helpers to ease the integration of
replica in `git` and `Make`.

## Roadmap

I keep track of the things I want to implement in a
[dedicated project](https://github.com/ReplicaTest/REPLica/projects/3).
If you think that something is missing, don't hesitate to submit a feature request.


## Help and support

PR are welcome.
If you use the tool, I'd be happy to know about it, drop me a line on
[twitter](https://twitter.com/berewt).

[dhall]: https://dhall-lang.org
[dhall-to-json]: https://github.com/dhall-lang/dhall-haskell/blob/master/dhall-json/README.md
[idris tests]: https://github.com/idris-lang/Idris2/tree/master/tests
[idris_repo]: https://github.com/idris-lang/Idris2
[idris_docker]: https://hub.docker.com/r/snazzybucket/idris2
[golden]: https://ro-che.info/articles/2017-12-04-golden-tests
[test file]: https://github.com/ReplicaTest/REPLica/blob/main/tests.dhall
[gitlab ci]: https://docs.gitlab.com/ee/ci/README.html
[github actions]: https://github.com/features/actions
