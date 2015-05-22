# Gush [![Build Status](https://travis-ci.org/pokonski/gush.svg?branch=master)](https://travis-ci.org/pokonski/gush)

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
  def configure
    run FetchJob1
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
    run FetchJob1, params: {url: "http://some.com/url"}
  end
end
```

See below to learn how to access those inside your job.

### Defining jobs

Jobs are classes inheriting from `Gush::Job`:

```ruby
#workflows/sample/fetch_job1.rb
class FetchJob1 < Gush::Job
  def work
    # do some fetching from remote APIs

    params #=> {url: "http://some.com/url"}
  end
end
```

`params` method is a hash containing your (optional) parameters passed to `run` method in the workflow.

### Running workflows

Now that we have defined our workflow we can use it:

#### 1. Initialize and save it

```ruby
flow = SampleWorkflow.new
flow.save # saves workflow and its jobs to Redis
```

**or:** you can also use a shortcut:

```ruby
flow = SampleWorkflow.create
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
