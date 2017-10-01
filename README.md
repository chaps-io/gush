# Gush [![Build Status](https://travis-ci.org/chaps-io/gush.svg?branch=master)](https://travis-ci.org/chaps-io/gush)

## [![](http://i.imgur.com/ya8Wnyl.png)](https://chaps.io) proudly made by [Chaps](https://chaps.io)

Gush is a parallel workflow runner using only Redis as storage and [ActiveJob](http://guides.rubyonrails.org/v4.2/active_job_basics.html#introduction) for scheduling and executing jobs.

## Theory

Gush relies on directed acyclic graphs to store dependencies, see [Parallelizing Operations With Dependencies](https://msdn.microsoft.com/en-us/magazine/dd569760.aspx) by Stephen Toub to learn more about this method.

## **WARNING - version notice **

This README is about the `1.0.0` version, which has breaking changes compared to < 1.0.0 versions. [See here for 0.4.1 documentation](https://github.com/chaps-io/gush/blob/349c5aff0332fd14b1cb517115c26d415aa24841/README.md).

## Installation

### 1. Add `gush` to Gemfile

```ruby
  gem 'gush', '~> 1.0.0'
```

### 2. Create `Gushfile`

When using Gush and its CLI commands you need a `Gushfile` in the root directory.
`Gushfile` should require all your workflows and jobs.

#### Ruby on Rails

For RoR it is enough to require the full environment:

```ruby
require_relative './config/environment.rb'
```

and make sure your jobs and workflows are correctly loaded by adding their directories to autoload_paths, inside `config/application.rb`:

```ruby
config.autoload_paths += ["#{Rails.root}/app/jobs", "#{Rails.root}/app/workflows"]
```

#### Ruby

Simply require any jobs and workflows manually in `Gushfile`:

```ruby
require_relative 'lib/workflows/example_workflow.rb'
require_relative 'lib/jobs/some_job.rb'
require_relative 'lib/jobs/some_other_job.rb'
```


## Example

The DSL for defining jobs consists of a single `run` method.
Here is a complete example of a workflow you can create:

```ruby
# app/workflows/sample_workflow.rb
class SampleWorkflow < Gush::Workflow
  def configure(url_to_fetch_from)
    run FetchJob1, params: { url: url_to_fetch_from }
    run FetchJob2, params: { some_flag: true, url: 'http://url.com' }

    run PersistJob1, after: FetchJob1
    run PersistJob2, after: FetchJob2

    run Normalize,
        after: [PersistJob1, PersistJob2],
        before: Index

    run Index
  end
end
```

and this is how the graph will look like:

![SampleWorkflow](http://i.imgur.com/SmeRRVT.png)

```
bundle exec gush viz SampleWorkflow
```


## Defining workflows

Let's start with the simplest workflow possible, consisting of a single job:

```ruby
class SimpleWorkflow < Gush::Workflow
  def configure
    run DownloadJob
  end
end
```

Of course having a workflow with only a single job does not make sense, so it's time to define dependencies:

```ruby
class SimpleWorkflow < Gush::Workflow
  def configure
    run DownloadJob
    run SaveJob, after: DownloadJob
  end
end
```

We just told Gush to execute `SaveJob` right after `DownloadJob` finishes **successfully**.

But what if your job must depend on more than one ancestor? Easy, just provide an array to the `after` attribute:

```ruby
class SimpleWorkflow < Gush::Workflow
  def configure
    run FirstDownloadJob
    run SecondDownloadJob

    run SaveJob, after: [FirstDownloadJob, SecondDownloadJob]
  end
end
```

Now `SaveJob` will only execute after both its ancestor finish without errors.

With this simple syntax you can build any complex workflows you can imagine!

#### Alternative way

`run` method also accepts `before:` attribute to define the opposite association. So we can write the same workflow as above, but like this:

```ruby
class SimpleWorkflow < Gush::Workflow
  def configure
    run FirstDownloadJob, before: SaveJob
    run SecondDownloadJob, before: SaveJob

    run SaveJob
  end
end
```

You can use whatever way you find more readable or even both at once :)

### Passing arguments to workflows

Workflows can accept any primitive arguments in their constructor, which then will be available in your
`configure` method.

Let's assume we are writing a book publishing workflow which needs to know where the PDF of the book is and under what ISBN it will be released:

```ruby
class PublishBookWorkflow < Gush::Workflow
  def configure(url, isbn)
    run FetchBook, params: { url: url }
    run PublishBook, params: { book_isbn: isbn }, after: FetchBook
  end
end
```

and then create your workflow with those arguments:

```ruby
PublishBookWorkflow.create("http://url.com/book.pdf", "978-0470081204")
```

and that's basically it for defining workflows, see below on how to define jobs:

## Defining jobs

The simplest job is a class inheriting from `Gush::Job` and responding to `perform` method. Much like any other ActiveJob class.

```ruby
class FetchBook < Gush::Job
  def perform
    # do some fetching from remote APIs
  end
end
```

But what about those params we passed in the previous step?

## Passing parameters into jobs

To do that, simply provide a `params:` attribute with a hash of parameters you'd like to have available inside the `perform` method of the job.

So, inside workflow:

```ruby
(...)
run FetchBook, params: {url: "http://url.com/book.pdf"}
(...)
```

and in the job we can access them like this:

```ruby
class FetchBook < Gush::Job
  def perform
    # you can access `params` method here, for example:

    params #=> {url: "http://url.com/book.pdf"}
  end
end
```

## Executing workflows

Now that we have defined our workflow and its jobs we can use it:

### 1. Start background worker process

The command to start background workers depends on the backend you chose for ActiveJob.
For example, in case of Sidekiq this would be:

```
bundle exec sidekiq -q gush
```

**Hint**: gush uses `gush` queue name by default. Keep that in mind, because some backends (like Sidekiq) will only run jobs from explicitly stated queues.

**[Click here to see backends section in official ActiveJob documentation about configuring backends](http://guides.rubyonrails.org/v4.2/active_job_basics.html#backends)**

### 2. Create the workflow instance

```ruby
flow = PublishBookWorkflow.create("http://url.com/book.pdf", "978-0470081204")
```

### 3. Start the workflow

```ruby
flow.start!
```

Now Gush will start processing jobs in the background using ActiveJob.

### 4. Monitor its progress:

```ruby
flow.reload
flow.status
#=> :running|:finished|:failed
```

`reload` is needed to see the latest status, since workflows are updated asynchronously.

## Advanced features

### Pipelining

Gush offers a useful tool to pass results of a job to its dependencies, so they can act differently.

**Example:**

Let's assume you have two jobs, `DownloadVideo`, `EncodeVideo`.
The latter needs to know where the first one save the file to be able to open it.


```ruby
class DownloadVideo < Gush::Job
  def perform
    downloader = VideoDownloader.fetch("http://youtube.com/?v=someytvideo")

    output(downloader.file_path)
  end
end
```

`output` method is used to ouput data from the job to all dependant jobs.

Now, since `DownloadVideo` finished and its dependant job `EncodeVideo` started, we can access that payload inside it:

```ruby
class EncodeVideo < Gush::Job
  def perform
    video_path = payloads.first[:output]
  end
end
```

`payloads` is an array containing outputs from all ancestor jobs. So for our `EncodeVide` job from above, the array will look like:

**Note:** Keep in mind that payloads can only contain data which **can be serialized as JSON**, because that's how Gush saves them to storage.

```ruby
[
  {
    id: "DownloadVideo-41bfb730-b49f-42ac-a808-156327989294" # unique id of the ancestor job
    class: "DownloadVideo",
    output: "https://s3.amazonaws.com/somebucket/downloaded-file.mp4" #the payload returned by DownloadVideo job using `output()` method
  }
]
```


## Command line interface (CLI)


### Checking status

- of a specific workflow:

  ```
  bundle exec gush show <workflow_id>
  ```

- of all created workflows:

  ```
  bundle exec gush list
  ```

### Vizualizing workflows as image

This requires that you have imagemagick installed on your computer:


```
bundle exec gush viz <NameOfTheWorkflow>
```

## Contributors

- [Mateusz Lenik](https://github.com/mlen)
- [Michał Krzyżanowski](https://github.com/krzyzak)
- [Maciej Nowak](https://github.com/keqi)
- [Maciej Kołek](https://github.com/ferusinfo)

## Contributing

1. Fork it ( http://github.com/chaps-io/gush/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
