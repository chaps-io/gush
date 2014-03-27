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

```
require_relative './lib/your_project'

Dir[Rowlf.root.join("workflows/**/*.rb")].each do |file|
  require file
end
```

### 1. Create a new workflow

```
gush create YourWorkflowClass
```

the command will return a unique workflow id you will use in later commands.

### 3. Run workers

This will start Sidekiq workers responsible for processing jobs.

```
gush workers
```

### 4. Start the workflow

```
gush start <workflow_id>
```

### 5. Check the status

```
gush show <workflow_id>

## Contributing

1. Fork it ( http://github.com/pokonski/gush/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
