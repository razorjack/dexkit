---
description: Use Dex::Form with Rails controllers, form_with, fields_for, strong params, and record-backed edit flows.
---

# Rails Integration

`Dex::Form` is built on ActiveModel, so it works with Rails form builders and controllers exactly as you'd expect.

## form_with

```erb
<%= form_with model: @form, url: employees_path do |f| %>
  <% if @form.errors.any? %>
    <ul>
      <% @form.errors.full_messages.each do |message| %>
        <li><%= message %></li>
      <% end %>
    </ul>
  <% end %>

  <%= f.text_field :first_name, placeholder: "First name" %>
  <%= f.text_field :last_name, placeholder: "Last name" %>
  <%= f.email_field :email, placeholder: "Email" %>
  <%= f.submit "Save" %>
<% end %>
```

## fields_for

Nested forms work with `fields_for`:

```erb
<%= form_with model: @form, url: employees_path do |f| %>
  <%= f.text_field :email %>

  <fieldset>
    <legend>Address</legend>
    <%= f.fields_for :address do |a| %>
      <%= a.text_field :street, placeholder: "Street" %>
      <%= a.text_field :city, placeholder: "City" %>
    <% end %>
  </fieldset>

  <fieldset>
    <legend>Emergency Contacts</legend>
    <%= f.fields_for :emergency_contacts do |c| %>
      <div>
        <%= c.text_field :name %>
        <%= c.text_field :phone %>
        <%= c.hidden_field :_destroy %>
        <button type="button"
          onclick="this.previousElementSibling.value='1'; this.parentElement.style.display='none'">
          Remove
        </button>
      </div>
    <% end %>
  </fieldset>

  <%= f.submit %>
<% end %>
```

Rails sends nested fields as `address_attributes` and `emergency_contacts_attributes` – the form handles both naming conventions automatically.

## model_name and routing

When you declare `model Employee` on your form, `model_name` delegates to `Employee.model_name`. This means `form_with model: @form` generates the correct routes and param keys:

```ruby
class Employee::Form < Dex::Form
  model Employee
  attribute :name, :string
end

form = Employee::Form.new(name: "Alice")
form.model_name.route_key  # => "employees"
form.model_name.param_key  # => "employee"
```

Without a `model` declaration, the form uses its own class name.

## persisted? and record

Rails uses `persisted?` to decide between POST (create) and PATCH (update). Bind a record with `with_record` to signal an edit:

```ruby
form = Employee::Form.new(name: "Alice").with_record(@employee)
form.persisted?  # => true (if @employee is persisted)
form.to_key      # => @employee.to_key (for URL generation)
form.to_param    # => @employee.to_param
```

`with_record` is chainable and returns the form instance. It's the recommended way to bind a record from controllers – see [why with_record?](#why-with-record) below.

## Strong parameters are optional

The form's `attribute` declarations are the whitelist – you don't need `permit`. Pass `params.require(...)` directly:

```ruby
@form = Employee::Form.new(params.require(:employee))
```

Undeclared attributes are silently dropped. `permit` still works if you prefer it, but it's redundant.

## Controller patterns

### Create

```ruby
class EmployeesController < ApplicationController
  def new
    @form = Employee::Form.new
  end

  def create
    @form = Employee::Form.new(params.require(:employee))

    if @form.save
      redirect_to dashboard_path
    else
      render :new, status: :unprocessable_entity
    end
  end
end
```

### Edit / Update

```ruby
class EmployeesController < ApplicationController
  def edit
    @form = Employee::Form.for(@employee)
  end

  def update
    @form = Employee::Form.new(params.require(:employee)).with_record(@employee)

    if @form.save
      redirect_to employee_path(@employee)
    else
      render :edit, status: :unprocessable_entity
    end
  end
end
```

The `.for` method is a convention you define on your form – see [Conventions](/form/conventions) for the full pattern.

## Why with_record? {#why-with-record}

`record` is a privileged attribute – it controls `persisted?`, `to_key`, and uniqueness exclusion. Because the form accepts controller params without `permit`, a `record` key in user-submitted data could sneak through if it were extracted from the params hash.

`with_record` solves this by keeping record binding separate from user input. It's a method call you make in your controller code, not something that can come from a form submission:

```ruby
# record comes from your controller, never from params
form = Employee::Form.new(params.require(:employee)).with_record(@employee)
```

For plain Ruby usage (tests, scripts), you can still pass `record` in the constructor hash:

```ruby
form = Employee::Form.new(name: "Alice", record: employee)
```
