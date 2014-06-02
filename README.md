# Gush

Gush is a parallel workflow runner using only Redis as its message broker and Sidekiq for workers.

## Installation

Add this line to your application's Gemfile:

    gem 'gush'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install gush

## Usage

Your project should contain a file called `Gushfile.rb` which loads all the necessary workflows for Sidekiq to use.

Example:

```ruby
require_relative './lib/your_project'

Dir[Rowlf.root.join("workflows/**/*.rb")].each do |file|
  require file
end
```

### Defining workflows

The DSL for defining jobs consists of a single `run` method. 
Here is a complete example of a workflow you can create:

```ruby
# workflows/sample_workflow.rb
class SampleWorkflow < Gush::Workflow
  def configure
    run FetchJob1
    run FetchJob2

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
### Defining jobs

Jobs are classes inheriting from `Gush::Job`:

```ruby
#workflows/sample/fetch_job1.rb
class FetchJob1 < Gush::Job
  def work
    # do some fetching from remote APIs
  end
end
```

### Running

#### 1. Register workflow

After you define your workflows and jobs, all you have to do is register them:

```
bundle exec gush create SampleWorkflow
```

the command will return a unique workflow id you will use in later commands.

#### 2. Run workers

This will start Sidekiq workers responsible for processing jobs

```
bundle exec gush workers
```

#### 3. Start the workflow

Use your workflow_id returned by `create` command.

```
bundle gush start <workflow_id>
```

### 5. Check the status

- of a specific workflow:

  ```
  bundle gush show <workflow_id>
  ```

- of all created workflows:
  
  ```
  bundle gush list
  ```


## Contributing

1. Fork it ( http://github.com/lonelyplanet/gush/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
