# Activecube::Graphql

The gem simplifies building GraphQL interfaces to analytical databases (OLAP).
For OLAP queries we use [Activecube](https://github.com/bitquery/activecube) gem.
Graphql is implemented by [Graphql](https://github.com/rmosolgo/graphql-ruby) gem.


## Installation

Add this line to your application's Gemfile:

```ruby
gem 'activecube-graphql'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install activecube-graphql

## Usage


### Field mapping

Activecube  must be mapped to a field using the following construct: 

```ruby
field_class Activecube::Graphql::CubeField

field :cube_name, [Response],  cube: CubeClass, null: true  do
  # cube arguments go here...
end
```

where:

* **CubeClass** is the class of your Activecube ( typically defined in Models)
* **Response** is the class for response. Typically it lists all possible metrics and dimensions

**NOTE!** All fields that used as dimensions and metrics, MUST have an extra field 'ast_node' defined as:

```ruby
    field :field, Types::Dimension::Field, extras: [:ast_node], null: true do
      argument :select, [FieldSelector], required: false
    end
```


### Connection mapping

If you have multiple database connections for many cubes, it can be convinient to define the mapping 
on the top level of GraphQL type:

```ruby

field :connect, CubeFieldClass, null: false do
  argument :database, Types::Enum::Databases, required: false
end

def your_field method, *args
  {
      database: args[0]  ? args[0][:database].to_sym : method.to_sym
  }
end
```


## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/bitquery/activecube-graphql. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [Contributor Covenant](http://contributor-covenant.org) code of conduct.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the Activecube::Graphql project’s codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/bitquery/activecube-graphql/blob/master/CODE_OF_CONDUCT.md).
