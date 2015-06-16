# Gush [![Build Status](https://travis-ci.org/chaps-io/gush.svg?branch=master)](https://travis-ci.org/chaps-io/gush)

## [![](http://i.imgur.com/ya8Wnyl.png)](https://chaps.io) proudly made by [Chaps](https://chaps.io)

Gush is a parallel workflow runner using only Redis as its message broker and Sidekiq for workers.

## Theory

Gush relies on directed acyclic graphs to store dependencies, see [Parallelizing Operations With Dependencies](https://msdn.microsoft.com/en-us/magazine/dd569760.aspx) by Stephen Toub.
## Installation

Add this line to your application's Gemfile:

    gem 'gush'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install gush

## Usage

### Defining workflows

The DSL for defining jobs consists of a single `run` method.
Here is a complete example of a workflow you can create:

```ruby
# workflows/sample_workflow.rb
class SampleWorkflow < Gush::Workflow
  def configure(url_to_fetch_from)
    run FetchJob1, params: { url: url_to_fetch_from }
    run FetchJob2, params: {some_flag: true, url: 'http://url.com'}

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
# workflows/sample_workflow.rb
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
class FetchJob1 < Gush::Job
  def work
    # do some fetching from remote APIs

    params #=> {url: "http://some.com/url"}
  end
end
```

`params` method is a hash containing your (optional) parameters passed to `run` method in the workflow.

#### Passing arguments to workflows

Workflows can accept any primitive arguments in their constructor, which then will be availabe in your
`configure` method.

Here's an example of a workflow responsible for publishing a book:

```ruby
# workflows/sample_workflow.rb
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
flow.save # saves workflow and its jobs to Redis
```

**or:** you can also use a shortcut:

```ruby
flow = SampleWorkflow.create(optional, arguments)
```

#### 2. Start workflow

First you need to start Sidekiq workers:

```
bundle exec gush workers
```

and then start your workflow:

```ruby
flow.start!
```

Now Gush will start processing jobs in background using Sidekiq
in the order defined in `configure` method inside Workflow.

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
    video_path = payloads["DownloadVideo"]
  end
end
```

`payloads` is a hash containing outputs from all parent jobs, where job class names are the keys.

**Note:** `payloads` will only contain outputs of the job's ancestors. So if job `A` depends on `B` and `C`,
the `paylods` hash will look like this:

```ruby
{
  "B" => (...),
  "C" => (...)
}
```


### Checking status:

#### In Ruby:

```ruby
flow.reload
flow.status
#=> :running|:pending|:finished|:failed
```

`reload` is needed to see the latest status, since workflows are updated asynchronously.

#### Via CLI:

- of a specific workflow:

  ```
  bundle gush show <workflow_id>
  ```

- of all created workflows:

  ```
  bundle gush list
  ```


### Requiring workflows inside your projects

**Skip this step if using Gush inside Rails application, workflows will already be loaded**

When using Gush and its CLI commands you need a Gushfile.rb in root directory.
Gushfile should require all your Workflows and jobs, for example:

```ruby
require_relative './lib/your_project'

Dir[Rails.root.join("app/workflows/**/*.rb")].each do |file|
  require file
end
```

## Contributors

- [Mateusz Lenik](https://github.com/mlen)
- [Michał Krzyżanowski](https://github.com/krzyzak)

## Contributing

1. Fork it ( http://github.com/pokonski/gush/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
