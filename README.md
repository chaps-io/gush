# Gush

![Gem Version](https://img.shields.io/gem/v/gush)
![GitHub Actions Workflow Status](https://img.shields.io/github/actions/workflow/status/chaps-io/gush/ruby.yml)


Gush is a parallel workflow runner using only Redis as storage and [ActiveJob](http://guides.rubyonrails.org/v4.2/active_job_basics.html#introduction) for scheduling and executing jobs.

## Theory

Gush relies on directed acyclic graphs to store dependencies, see [Parallelizing Operations With Dependencies](https://msdn.microsoft.com/en-us/magazine/dd569760.aspx) by Stephen Toub to learn more about this method.

## **WARNING - version notice**

This README is about the latest `master` code, which might differ from what is released on RubyGems. See tags to browse previous READMEs.

## Installation

### 1. Add `gush` to Gemfile

```ruby
gem 'gush', '~> 4.2'
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

```mermaid
graph TD
    A{Start} --> B[FetchJob1]
    A --> C[FetchJob2]
    B --> D[PersistJob1]
    C --> E[PersistJob2]
    D --> F[NormalizeJob]
    E --> F
    F --> G[IndexJob]
    G --> H{Finish}
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

But what if your job must have multiple dependencies? That's easy, just provide an array to the `after` attribute:

```ruby
class SimpleWorkflow < Gush::Workflow
  def configure
    run FirstDownloadJob
    run SecondDownloadJob

    run SaveJob, after: [FirstDownloadJob, SecondDownloadJob]
  end
end
```

Now `SaveJob` will only execute after both its parents finish without errors.

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
  def configure(url, isbn, publish: false)
    run FetchBook, params: { url: url }
    if publish
      run PublishBook, params: { book_isbn: isbn }, after: FetchBook
    end
  end
end
```

and then create your workflow with those arguments:

```ruby
PublishBookWorkflow.create("http://url.com/book.pdf", "978-0470081204", publish: true)
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

and within the job we can access them like this:

```ruby
class FetchBook < Gush::Job
  def perform
    # you can access `params` method here, for example:

    params #=> {url: "http://url.com/book.pdf"}
  end
end
```

## Executing workflows

Now that we have defined our workflow and its jobs, we can use it:

### 1. Start background worker process

**Important**: The command to start background workers depends on the backend you chose for ActiveJob.
For example, in case of Sidekiq this would be:

```
bundle exec sidekiq -q gush
```

**[Click here to see backends section in official ActiveJob documentation about configuring backends](http://guides.rubyonrails.org/active_job_basics.html#backends)**

**Hint**: gush uses `gush` queue name by default. Keep that in mind, because some backends (like Sidekiq) will only run jobs from explicitly stated queues.


### 2. Create the workflow instance

```ruby
flow = PublishBookWorkflow.create("http://url.com/book.pdf", "978-0470081204")
```

### 3. Start the workflow

```ruby
flow.start!
```

Now Gush will start processing jobs in the background using ActiveJob and your chosen backend.

### 4. Monitor its progress:

```ruby
flow.reload
flow.status
#=> :running|:finished|:failed
```

`reload` is needed to see the latest status, since workflows are updated asynchronously.

## Loading workflows

### Finding a workflow by id

```
flow = Workflow.find(id)
```

### Paging through workflows

To get workflows with pagination, use start and stop (inclusive) index values:

```
flows = Workflow.page(0, 99)
```

Or in reverse order:

```
flows = Workflow.page(0, 99, order: :desc)
```

## Advanced features

### Global parameters for jobs

Workflows can accept a hash of `globals` that are automatically forwarded as parameters to all jobs.

This is useful to have common functionality across workflow and job classes, such as tracking the creator id for all instances:

```ruby
class SimpleWorkflow < Gush::Workflow
  def configure(url_to_fetch_from)
    run DownloadJob, params: { url: url_to_fetch_from }
  end
end

flow = SimpleWorkflow.create('http://foo.com', globals: { creator_id: 123 })
flow.globals
=> {:creator_id=>123}
flow.jobs.first.params
=> {:creator_id=>123, :url=>"http://foo.com"}
```

**Note:** job params with the same key as globals will take precedence over the globals.


### Pipelining

Gush offers a useful tool to pass results of a job to its dependencies, so they can act differently.

**Example:**

Let's assume you have two jobs, `DownloadVideo`, `EncodeVideo`.
The latter needs to know where the first one saved the file to be able to open it.


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

`payloads` is an array containing outputs from all ancestor jobs. So for our `EncodeVideo` job from above, the array will look like:


```ruby
[
  {
    id: "DownloadVideo-41bfb730-b49f-42ac-a808-156327989294" # unique id of the ancestor job
    class: "DownloadVideo",
    output: "https://s3.amazonaws.com/somebucket/downloaded-file.mp4" #the payload returned by DownloadVideo job using `output()` method
  }
]
```

**Note:** Keep in mind that payloads can only contain data which **can be serialized as JSON**, because that's how Gush stores them internally.

### Dynamic workflows

There might be a case when you have to construct the workflow dynamically depending on the input.

As an example, let's write a workflow which accepts an array of users and has to send an email to each one. Additionally after it sends the e-mail to every user, it also has to notify the admin about finishing.


```ruby

class NotifyWorkflow < Gush::Workflow
  def configure(user_ids)
    notification_jobs = user_ids.map do |user_id|
      run NotificationJob, params: {user_id: user_id}
    end

    run AdminNotificationJob, after: notification_jobs
  end
end
```

We can achieve that because `run` method returns the id of the created job, which we can use for chaining dependencies.

Now, when we create the workflow like this:

```ruby
flow = NotifyWorkflow.create([54, 21, 24, 154, 65]) # 5 user ids as an argument
```

it will generate a workflow with 5 `NotificationJob`s and one `AdminNotificationJob` which will depend on all of them:


```mermaid
graph TD
    A{Start} --> B[NotificationJob]
    A --> C[NotificationJob]
    A --> D[NotificationJob]
    A --> E[NotificationJob]
    A --> F[NotificationJob]
    B --> G[AdminNotificationJob]
    C --> G
    D --> G
    E --> G
    F --> G
    G --> H{Finish}
```

### Dynamic queue for jobs

There might be a case you want to configure different jobs in the workflow using different queues. Based on the above the example, we want to config `AdminNotificationJob` to use queue `admin` and `NotificationJob` use queue `user`.

```ruby

class NotifyWorkflow < Gush::Workflow
  def configure(user_ids)
    notification_jobs = user_ids.map do |user_id|
      run NotificationJob, params: {user_id: user_id}, queue: 'user'
    end

    run AdminNotificationJob, after: notification_jobs, queue: 'admin'
  end
end
```

### Dynamic waitable time for jobs

There might be a case you want to configure a job to be executed after a time. Based on above example, we want to configure `AdminNotificationJob` to be executed after 5 seconds.

```ruby

class NotifyWorkflow < Gush::Workflow
  def configure(user_ids)
    notification_jobs = user_ids.map do |user_id|
      run NotificationJob, params: {user_id: user_id}, queue: 'user'
    end

    run AdminNotificationJob, after: notification_jobs, queue: 'admin', wait: 5.seconds
  end
end
```

### Customization of ActiveJob enqueueing

There might be a case when you want to customize enqueing a job with more than just the above two options (`queue` and `wait`).

To pass additional options to `ActiveJob.set`, override `Job#worker_options`, e.g.:

```ruby

class ScheduledJob < Gush::Job

  def worker_options
    super.merge(wait_until: Time.at(params[:start_at]))
  end

end
```

Or to entirely customize the ActiveJob integration, override `Job#enqueue_worker!`, e.g.:

```ruby

class SynchronousJob < Gush::Job

  def enqueue_worker!(options = {})
    Gush::Worker.perform_now(workflow_id, name)
  end

end
```


## Command line interface (CLI)

### Checking status

- of a specific workflow:

  ```
  bundle exec gush show <workflow_id>
  ```

- of a page of workflows:

  ```
  bundle exec gush list
  ```

- of the most recent 100 workflows

  ```
  bundle exec gush list -99 -1
  ```

### Vizualizing workflows as image

This requires that you have imagemagick installed on your computer:


```
bundle exec gush viz <NameOfTheWorkflow>
```

### Customizing locking options

In order to prevent getting the RedisMutex::LockError error when having a large number of jobs, you can customize these 2 fields `locking_duration` and `polling_interval` as below

```ruby
# config/initializers/gush.rb
Gush.configure do |config|
  config.redis_url = "redis://localhost:6379"
  config.concurrency = 5
  config.locking_duration = 2 # how long you want to wait for the lock to be released, in seconds
  config.polling_interval = 0.3 # how long the polling interval should be, in seconds
end
```

### Cleaning up afterwards

Running `NotifyWorkflow.create` inserts multiple keys into Redis every time it is run.  This data might be useful for analysis but at a certain point it can be purged.  By default gush and Redis will keep keys forever.  To configure expiration you need to do two things.

1. Create an initializer that specifies `config.ttl` in seconds. Best NOT to set TTL to be too short (like minutes) but about a week in length.

```ruby
# config/initializers/gush.rb
Gush.configure do |config|
  config.redis_url = "redis://localhost:6379"
  config.concurrency = 5
  config.ttl = 3600*24*7
end
```

2. Call `Client#expire_workflows` periodically, which will clear all expired stored workflow and job data and indexes. This method can be called at any rate, but ideally should be called at least once for every 1000 workflows created.

If you need more control over individual workflow expiration, you can call `flow.expire!(ttl)` with a TTL different from the Gush configuration, or with -1 to never expire the workflow.

### Avoid overlapping workflows

Since we do not know how long our workflow execution will take we might want to avoid starting the next scheduled workflow iteration while the current one with same class is still running.  Long term this could be moved into core library, perhaps `Workflow.find_by_class(klass)`

```ruby
# config/initializers/gush.rb
GUSH_CLIENT = Gush::Client.new
# call this method before NotifyWorkflow.create
def find_by_class klass
  GUSH_CLIENT.all_workflows.each do |flow|
    return true if flow.to_hash[:name] == klass && flow.running?
  end
  return false
end
```

## Gush 3.0 Migration

Gush 3.0 adds indexing for fast workflow pagination and changes the mechanism for expiring workflow data from Redis.

### Migration

Run `bundle exec gush migrate` after upgrading. This will update internal data structures.

### Expiration API

Periodically run `Gush::Client.new.expire_workflows` to expire data. Workflows will be automatically enrolled in this expiration, so there is no longer a need to call `workflow.expire!`.


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
