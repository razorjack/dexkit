---
description: Recommended Dex::Form conventions – .for loaders, with_record binding, save methods, and operation-backed persistence.
---

# Conventions

`Dex::Form` handles data holding, normalization, and validation. Persistence and record mapping are your responsibility – the form doesn't know (or care) how your data gets saved. These are the recommended patterns.

## .for – loading from a record

Define a class method that maps record attributes to form attributes and binds the record:

```ruby
class Employee::Form < Dex::Form
  model Employee

  attribute :name, :string
  attribute :email, :string

  def self.for(employee)
    new(name: employee.name, email: employee.email).with_record(employee)
  end
end
```

```ruby
@form = Employee::Form.for(@employee)
```

`with_record` sets `persisted?` to true and gives the uniqueness validator a record to exclude.

### Multi-model forms

This is where form objects really shine. When a single form spans multiple models, `.for` maps each model's data into the flat form structure:

```ruby
class Employee::OnboardingForm < Dex::Form
  attribute :first_name, :string
  attribute :last_name, :string
  attribute :email, :string
  attribute :department, :string
  attribute :position, :string
  attribute :start_date, :date

  normalizes :email, with: -> { _1&.strip&.downcase.presence }

  validates :email, presence: true, uniqueness: { model: Employee }
  validates :first_name, :last_name, :department, :position, presence: true

  nested_one :address do
    attribute :street, :string
    attribute :city, :string
    attribute :postal_code, :string
    attribute :country, :string
    validates :street, :city, :country, presence: true
  end

  nested_many :emergency_contacts do
    attribute :name, :string
    attribute :phone, :string
    validates :name, :phone, presence: true
  end

  def self.for(employee)
    new(
      first_name: employee.first_name,
      last_name: employee.last_name,
      email: employee.email,
      department: employee.department.name,
      position: employee.position.title,
      start_date: employee.start_date,
      address: {
        street: employee.address.street,
        city: employee.address.city,
        postal_code: employee.address.postal_code,
        country: employee.address.country
      },
      emergency_contacts: employee.emergency_contacts.map { |c|
        { name: c.name, phone: c.phone }
      }
    ).with_record(employee)
  end
end
```

## #save – persisting with an Operation

The `save` method validates the form and delegates persistence to whatever makes sense for your app. The cleanest pattern uses a `Dex::Operation`:

```ruby
class Employee::OnboardingForm < Dex::Form
  # ... attributes, validations, nested forms ...

  def save
    return false unless valid?

    case operation.safe.call
    in Ok then true
    in Err => e then errors.add(:base, e.message) and false
    end
  end

  private

  def operation
    Employee::Onboard.new(
      employee: record, first_name:, last_name:, email:,
      department:, position:, start_date:,
      address: address.to_h,
      emergency_contacts: emergency_contacts.map(&:to_h)
    )
  end
end
```

The Operation handles all the multi-model persistence – creating or updating Employee, Department, and Position inside a transaction:

```ruby
class Employee::Onboard < Dex::Operation
  prop :employee, _Nilable(Employee)
  prop :first_name, String
  prop :last_name, String
  prop :email, String
  prop :department, String
  prop :position, String
  prop :start_date, Date
  prop :address, Hash
  prop :emergency_contacts, _Array(Hash)

  def perform
    emp = self.employee || Employee.new
    emp.update!(first_name:, last_name:, email:)

    dept = Department.find_or_create_by!(name: department)
    emp.update!(department: dept, position: Position.find_by!(title: position), start_date:)

    sync_emergency_contacts(emp)

    emp
  end
end
```

### Simple persistence

For single-model forms, you can skip the Operation:

```ruby
def save
  return false unless valid?

  target = record || Employee.new
  target.update(name:, email:)
end
```

## Controller pattern

No `permit` needed – the form's attribute declarations are the whitelist. Just `require` the top-level key:

```ruby
class EmployeesController < ApplicationController
  def new
    @form = Employee::OnboardingForm.new
  end

  def create
    @form = Employee::OnboardingForm.new(params.require(:employee))

    if @form.save
      redirect_to dashboard_path
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @form = Employee::OnboardingForm.for(@employee)
  end

  def update
    @form = Employee::OnboardingForm.new(params.require(:employee)).with_record(@employee)

    if @form.save
      redirect_to dashboard_path
    else
      render :edit, status: :unprocessable_entity
    end
  end
end
```

## Testing

Forms are standard ActiveModel objects. Test them with plain Minitest – no special helpers needed:

```ruby
class EmployeeOnboardingFormTest < Minitest::Test
  def test_validates_required_fields
    form = Employee::OnboardingForm.new
    assert form.invalid?
    assert form.errors[:email].any?
    assert form.errors[:first_name].any?
  end

  def test_normalizes_email
    form = Employee::OnboardingForm.new(email: "  ALICE@EXAMPLE.COM  ")
    assert_equal "alice@example.com", form.email
  end

  def test_nested_validation
    form = Employee::OnboardingForm.new(
      first_name: "Alice", last_name: "Smith",
      email: "alice@example.com",
      department: "Engineering", position: "Dev",
      start_date: Date.today,
      address: { street: "", city: "", country: "" }
    )
    assert form.invalid?
    assert form.errors[:"address.street"].any?
  end

  def test_serialization
    form = Employee::OnboardingForm.new(
      first_name: "Alice", email: "alice@example.com",
      address: { street: "123 Main", city: "NYC" }
    )
    h = form.to_h
    assert_equal "Alice", h[:first_name]
    assert_equal "123 Main", h[:address][:street]
  end
end
```
