Feature: Testing Vhosts
    This feature is to be used to create and manage vhosts

    Background: Provision the server
        Given that I have vm config file "test.yaml"
        Then I create the vm "test"
        Then I should check the status of "test" is "running"

    Scenario: Check the server has powered on correctly
        Given that I want to confirm the server "test" has been provisioned
        Then I should ping the server "test"
        And I should be able to connect to "test" on port "22"

    Scenario: Destroy the server
        Given that I want to destroy the server "test"
        Then I should destroy the server
        Then I should undefine the server

