# github-replacer
Content Replace and Create Pull Request(like a dependabot)

## What is this?

github-replace provide replacing some content for Github API.
you can define replace rule with regexp.


## Usage

```bash
$ docker run -e GITHUB_TOKEN=$GITHUB_TOKEN -e CONFIG_PATH=/tmp/config.yml -v `pwd`/config.yml:/tmp/config.yml pyama/github-replacer
```

## Config

You can define config for contents replace.

```yaml
update-container-image-name:
  repo_pattern: "pyama86/.*"
  file_pattern: ".github/.*"
  content_pattern: "container: example"
  replace: "container: example2"
```
- config name(cf. update-container-image-name)

your config name.

- repo_pattern

filter repository by regexp.

- file_pattern

filter flle by regexp.

- content_pattern

search content in some file by regexp.

- replace

replace content from matching content pattern.
