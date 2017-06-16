# Gush [![Build Status](https://travis-ci.org/chaps-io/gush.svg?branch=master)](https://travis-ci.org/chaps-io/gush)

## [![](http://i.imgur.com/ya8Wnyl.png)](https://chaps.io) proudly made by [Chaps](https://chaps.io)

Gush is a parallel workflow runner using only Redis as storage and [ActiveJob](http://guides.rubyonrails.org/v4.2/active_job_basics.html#introduction) for scheduling and executing jobs.

## Theory

Gush relies on directed acyclic graphs to store dependencies, see [Parallelizing Operations With Dependencies](https://msdn.microsoft.com/en-us/magazine/dd569760.aspx) by Stephen Toub to learn more about this method.

## **WARNING - version notice **

This README is about the `1.0.0` version, which has breaking changes compared to < 1.0.0 versions. [See here for 0.4.1 documentation](https://github.com/chaps-io/gush/blob/349c5aff0332fd14b1cb517115c26d415aa24841/README.md).

## Installation

Add this line to your application's Gemfile:

    gem 'gush'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install gush


### Requiring workflows inside your project

When using Gush and its CLI commands you need a `Gushfile` in root directory.
`Gushfile` should require all your workflows and jobs.

#### Ruby on Rails

```ruby
require_relative './config/environment.rb'
```

and make sure your jobs and workflows are correctly loaded by adding their directories to autoload_paths, inside `config/application.rb`:

```ruby
config.autoload_paths += ["#{Rails.root}/app/jobs", "#{Rails.root}/app/workflows"]
```

#### Non-Rails apps

Simply require any jobs and workflows manually in `Gushfile`:

```ruby
require_relative 'lib/workflows/example_workflow.rb'
require_relative 'lib/jobs/some_job.rb'
require_relative 'lib/jobs/some_other_job.rb'
```


## Usage

### Defining workflows

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

**Hint:** For debugging purposes you can vizualize the graph using `viz` command:

```
bundle exec gush viz SampleWorkflow
```

For the Workflow above, the graph will look like this:

![SampleWorkflow](http://i.imgur.com/SmeRRVT.png)


#### Passing parameters to jobs

You can pass any primitive arguments into jobs while defining your workflow:

```ruby
# app/workflows/sample_workflow.rb

class SampleWorkflow < Gush::Workflow
  def configure
    run FetchJob1, params: { url: "http://some.com/url" }
  end
end
```

See below to learn how to access those params inside your job.

#### Defining jobs

Jobs are classes inheriting from `Gush::Job`:

```ruby
# app/jobs/fetch_job.rb

class FetchJob < Gush::Job
  def work
    # do some fetching from remote APIs

    params #=> {url: "http://some.com/url"}
  end
end
```

`params` method is a hash containing your (optional) parameters passed to `run` method in the workflow.

#### Passing arguments to workflows

Workflows can accept any primitive arguments in their constructor, which then will be available in your
`configure` method.

Here's an example of a workflow responsible for publishing a book:

```ruby
# app/workflows/sample_workflow.rb
class PublishBookWorkflow < Gush::Workflow
  def configure(url, isbn)
    run FetchBook, params: { url: url }
    run PublishBook, params: { book_isbn: isbn }
  end
end
```

and then create your workflow with those arguments:

```ruby
PublishBookWorkflow.new("http://url.com/book.pdf", "978-0470081204")
```


### Running workflows

Now that we have defined our workflow we can use it:

#### 1. Initialize and save it

```ruby
flow = SampleWorkflow.new(optional, arguments)
flow.save # saves workflow and its jobs to Redis storage
```

**or:** you can also use a shortcut:

```ruby
flow = SampleWorkflow.create(optional, arguments)
```

#### 2. Run background worker processes

The command to start background workers depends on the backend you chose for ActiveJob.
For example, in case of Sidekiq this would be:

```
bundle exec sidekiq
```


#### 3. Start the workflow

```ruby
flow.start!
```

Now Gush will start processing jobs in background using ActiveJob
in the order defined in `configure` method inside Workflow.

**[See Backends section in official ActiveJob documentation about configuring backends](http://guides.rubyonrails.org/v4.2/active_job_basics.html#backends)**

### Pipelining

Gush offers a useful feature which lets you pass results of a job to its dependencies, so they can act accordingly.

**Example:**

Let's assume you have two jobs, `DownloadVideo`, `EncodeVideo`.
The latter needs to know where the first one downloaded the file to be able to open it.


```ruby
class DownloadVideo < Gush::Job
  def work
    downloader = VideoDownloader.fetch("http://youtube.com/?v=someytvideo")

    output(downloader.file_path)
  end
end
```

`output` method is Gush's way of saying: "I want to pass this down to my descendants".

Now, since `DownloadVideo` finished and its dependant job `EncodeVideo` started, we can access that payload down the (pipe)line:

```ruby
class EncodeVideo < Gush::Job
  def work
    video_path = payloads.first[:output]
  end
end
```

`payloads` is an array containing outputs from all ancestor jobs. So if job `A` depends on `B` and `C`,
the `payloads` array will look like this:


```ruby
[
  {
    id: "B-deafd12352"
    class: "B",
    output: "some output job B returned"
  },
  {
    id: "C-feadfga23"
    class: "C",
    output: "some other output job C returned"
  }
]
```


### Checking status:

#### In Ruby:

```ruby
flow.reload
flow.status
#=> :running|:finished|:failed
```

`reload` is needed to see the latest status, since workflows are updated asynchronously.

#### Via CLI:

- of a specific workflow:

  ```
  bundle exec gush show <workflow_id>
  ```

- of all created workflows:

  ```
  bundle exec gush list
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
